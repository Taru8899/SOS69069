// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/**
 * @title SOS69069 Presence Logger
 * @author SOS69069
 * @notice Permissionless, fund-free logger for compact Presence records.
 * @dev
 * Core design decisions:
 * - id = block.timestamp (uint40). Only one Presence may be logged per second.
 * - Poster address is NEVER stored in the Presence struct; it appears only in
 *   the PresenceLogged event and in the historical posterPresenceIds index.
 * - priceInReturn (5 bytes) and method (1 byte) are packed into a single bytes6.
 * - contact is fixed-size bytes15.
 * - Total storage per live Presence = 4 slots.
 * - Hard capacity of MAX_LIVE_PRESENCES (1 000 000) enforced by a fixed-size
 *   circular buffer (liveQueue). The buffer never grows beyond the cap;
 *   oldest entries are overwritten / erased in strict order.
 * - Once the capacity has ever been reached, anyone may call eraseOldest()
 *   to delete the current oldest record and claim the gas refund.
 *
 * Business rules (unchanged):
 * 1. Caller must have pushCountOf(msg.sender) > 0 on the SOS contract.
 * 2. Every successful logPresence executes sos.pushTo(CREATOR) (1 SOS mint).
 * 3. FOR_YOU ('Y') requires effective (trust - push) > amount.
 *    FOR_ME ('M') has no effective restriction.
 *
 * SOS contract : 0x61af906f53Eb927790055AC8eA99916a01873c15
 * CREATOR      : 0x1C10e6574ee696f54b21A611a21313E4714628ad
 */

interface ISOS {
    /// @notice Returns the SOS trust balance of an account.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns how many times an account has called pushTo.
    function pushCountOf(address user) external view returns (uint256);

    /// @notice Mints exactly 1 SOS unit to `to`. Permissionless.
    function pushTo(address to) external;
}

/**
 * @title PresenceLogger
 * @notice Compact on-chain Presence logger with creator-mint enforcement
 *         and a hard 1 000 000 live-record capacity using a circular buffer.
 */
contract PresenceLogger {

    /// @notice Address of the external SOS contract.
    address public constant SOS_CONTRACT = 0x61af906f53Eb927790055AC8eA99916a01873c15;

    /// @notice Address that receives the mandatory 1 SOS mint on every post.
    address public constant CREATOR = 0x1C10e6574ee696f54b21A611a21313E4714628ad;

    /// @notice Maximum number of simultaneously live Presence records.
    uint256 public constant MAX_LIVE_PRESENCES = 1_000_000;

    /// @notice Immutable reference to the SOS contract.
    ISOS public immutable sos;

    /**
     * @notice Compact Presence record (exactly 4 storage slots).
     * @dev Layout:
     *      slot 0 : id (uint40) + pType (bytes1) + priceAndMethod (bytes6)
     *      slot 1 : amount
     *      slot 2 : contact (bytes15)
     *      slot 3 : effective
     * @param id            block.timestamp at creation (also the mapping key)
     * @param pType         'Y' = FOR_YOU, 'M' = FOR_ME
     * @param priceAndMethod byte[0] = method, bytes[1..5] = priceInReturn
     * @param amount        Amount in SOS units
     * @param contact       Fixed-size contact data (max 15 bytes)
     * @param effective     Snapshot of (trust - push) at post time
     */
    struct Presence {
        uint40  id;
        bytes1  pType;
        bytes6  priceAndMethod;
        uint256 amount;
        bytes15 contact;
        int256  effective;
    }

    /// @notice Presence records keyed by timestamp (id).
    mapping(uint256 => Presence) public presences;

    /// @notice Append-only historical list of ids created by each poster.
    /// @dev Never pruned. Use the paginated getter.
    mapping(address => uint256[]) public posterPresenceIds;

    /// @notice Fixed-size circular buffer of live ids.
    /// @dev Length is permanently MAX_LIVE_PRESENCES. Indices wrap around.
    ///      Only the range [liveQueueStart, liveQueueStart + liveCount) (mod MAX)
    ///      contains valid live ids.
    uint256[MAX_LIVE_PRESENCES] private liveQueue;

    /// @notice Index of the oldest live entry inside the circular buffer.
    uint256 public liveQueueStart;

    /// @notice Current number of live entries (0 … MAX_LIVE_PRESENCES).
    uint256 public liveCount;

    /// @notice Total number of Presence ids ever issued (monotonic).
    uint256 public totalLogged;

    /// @notice Becomes true the first time live count reaches MAX_LIVE_PRESENCES.
    /// @dev Once true, anyone may call eraseOldest().
    bool public capacityReached;

    /**
     * @notice Emitted when a new Presence is successfully logged.
     * @param id            block.timestamp used as id
     * @param poster        msg.sender (emitted only – never stored)
     * @param pType         'Y' or 'M'
     * @param amount        Amount in SOS units
     * @param priceInReturn 5-byte price data
     * @param method        Single-byte method code
     * @param contact       15-byte contact data
     * @param effective     Snapshot of (trust - push)
     * @param timestamp     block.timestamp (same as id)
     */
    event PresenceLogged(
        uint256 indexed id,
        address indexed poster,
        bytes1  pType,
        uint256 amount,
        bytes5  priceInReturn,
        bytes1  method,
        bytes15 contact,
        int256  effective,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a Presence is erased (auto or manual).
     * @param id        The erased id (timestamp)
     * @param erasedBy  Address that triggered the erasure
     * @param erasedAt  block.timestamp of erasure
     */
    event PresenceErased(
        uint256 indexed id,
        address erasedBy,
        uint256 erasedAt
    );

    /**
     * @notice Deploys the logger and binds it permanently to the SOS contract.
     */
    constructor() {
        sos = ISOS(SOS_CONTRACT);
    }

    /**
     * @notice Logs a new Presence.
     * @dev Order of operations: validation → standing check → effective check
     *      → mandatory creator mint → capacity enforcement → storage write → event.
     *      Only one Presence may be created per second (id = block.timestamp).
     *      When the circular buffer is full the oldest entry is erased first.
     *      Local variables are carefully scoped to avoid "Stack too deep".
     * @param pType          'Y' = FOR_YOU, 'M' = FOR_ME
     * @param amount         Amount in SOS units (must be > 0)
     * @param priceInReturn  Exactly 5 bytes describing the asked/offered value
     * @param method         Single-byte payment/contact method code
     * @param contact        Exactly 15 bytes of contact information
     * @return id            The assigned id (= block.timestamp)
     */
    function logPresence(
        bytes1 pType,
        uint256 amount,
        bytes5 priceInReturn,
        bytes1 method,
        bytes15 contact
    ) external returns (uint256 id) {
        require(pType == bytes1("Y") || pType == bytes1("M"), "Type must be Y or M");
        require(amount > 0, "Amount must be > 0");
        require(priceInReturn != bytes5(0), "priceInReturn required");
        require(contact != bytes15(0), "contact required");

        // --- Standing + effective checks (scoped to free stack) ---
        {
            uint256 push = sos.pushCountOf(msg.sender);
            require(push > 0, "Must call pushForMe (or any pushTo) on SOS first");

            uint256 trust = sos.balanceOf(msg.sender);
            int256 effective = _safeEffective(trust, push);

            if (pType == bytes1("Y")) {
                require(amount <= uint256(type(int256).max), "amount exceeds int256 range");
                require(effective > int256(amount), "Effective must exceed amount for FOR_YOU");
            }

            // Mandatory 1 SOS mint to CREATOR
            sos.pushTo(CREATOR);

            // Store effective temporarily in the return variable? No – keep it local only inside block.
            // We re-compute later only if needed, but to avoid re-reading we pass it out via a helper.
            id = _writePresence(pType, amount, priceInReturn, method, contact, effective);
        }
    }

    /**
     * @dev Internal writer that keeps the stack shallow for the external function.
     *      Performs id assignment, capacity management, storage write and event.
     */
    function _writePresence(
        bytes1 pType,
        uint256 amount,
        bytes5 priceInReturn,
        bytes1 method,
        bytes15 contact,
        int256 effective
    ) internal returns (uint256 id) {
        id = block.timestamp;
        require(presences[id].id == 0, "id already used");

        // Capacity enforcement via circular buffer
        if (liveCount == MAX_LIVE_PRESENCES) {
            _eraseOldest(address(this));
            capacityReached = true;
        } else if (liveCount + 1 == MAX_LIVE_PRESENCES) {
            capacityReached = true;
        }

        // Pack method (1 byte) + priceInReturn (5 bytes) into bytes6
        bytes6 packed;
        assembly {
            packed := or(shl(40, method), priceInReturn)
        }

        Presence storage p = presences[id];
        p.id             = uint40(id);
        p.pType          = pType;
        p.priceAndMethod = packed;
        p.amount         = amount;
        p.contact        = contact;
        p.effective      = effective;

        // Write into the circular buffer
        uint256 writeIndex = (liveQueueStart + liveCount) % MAX_LIVE_PRESENCES;
        liveQueue[writeIndex] = id;
        unchecked { liveCount++; }

        posterPresenceIds[msg.sender].push(id);
        unchecked { totalLogged++; }

        // Emit with minimal extra locals
        _emitLogged(id, pType, amount, priceInReturn, method, contact, effective);
    }

    /**
     * @dev Separate emit helper – keeps stack depth low in the caller.
     */
    function _emitLogged(
        uint256 id,
        bytes1 pType,
        uint256 amount,
        bytes5 priceInReturn,
        bytes1 method,
        bytes15 contact,
        int256 effective
    ) internal {
        emit PresenceLogged(
            id,
            msg.sender,
            pType,
            amount,
            priceInReturn,
            method,
            contact,
            effective,
            block.timestamp
        );
    }

    /**
     * @notice Deletes the current oldest Presence in strict order.
     * @dev Callable by anyone only after the live capacity of 1 000 000
     *      has been reached at least once. The caller receives the gas
     *      refund from clearing the storage slots.
     */
    function eraseOldest() external {
        require(capacityReached, "Capacity of 1 000 000 not yet reached");
        require(liveCount > 0, "Nothing left to erase");
        _eraseOldest(msg.sender);
    }

    /**
     * @dev Internal helper that erases the oldest live record and advances
     *      the circular-buffer pointer. Used by both auto-prune and eraseOldest().
     * @param erasedBy Address recorded in the PresenceErased event.
     */
    function _eraseOldest(address erasedBy) internal {
        uint256 oldId = liveQueue[liveQueueStart];
        if (presences[oldId].id != 0) {
            delete presences[oldId];
            emit PresenceErased(oldId, erasedBy, block.timestamp);
        }
        // Clear the slot (keeps the buffer clean)
        liveQueue[liveQueueStart] = 0;
        unchecked {
            liveQueueStart = (liveQueueStart + 1) % MAX_LIVE_PRESENCES;
            liveCount--;
        }
    }

    /**
     * @notice Returns true if the given id has been erased (or never existed).
     * @param id The Presence id (timestamp) to check.
     * @return expired True when the record is no longer present.
     */
    function isExpired(uint256 id) public view returns (bool expired) {
        expired = (presences[id].id == 0) && (id > 0);
    }

    /**
     * @dev Overflow-safe computation of (trust - push) as int256.
     * @param trust SOS balance of the account.
     * @param push  SOS push count of the account.
     * @return result Signed effective value.
     */
    function _safeEffective(uint256 trust, uint256 push) internal pure returns (int256 result) {
        uint256 maxInt = uint256(type(int256).max);
        require(trust <= maxInt, "trust exceeds int256 range");
        require(push <= maxInt, "push exceeds int256 range");
        result = int256(trust) - int256(push);
    }

    /**
     * @notice Returns the full Presence record for a given id.
     * @dev Reverts if the record has been erased or never existed.
     * @param id The Presence id (timestamp).
     * @return p The Presence struct.
     */
    function getPresence(uint256 id) external view returns (Presence memory p) {
        p = presences[id];
        require(p.id != 0, "Presence erased or nonexistent");
    }

    /**
     * @notice Paginated view of a poster's historical ids.
     * @param poster Address whose history should be returned.
     * @param start  Zero-based start index.
     * @param count  Maximum number of entries to return.
     * @return ids   Slice of the historical list.
     */
    function getPosterPresenceIds(
        address poster,
        uint256 start,
        uint256 count
    ) external view returns (uint256[] memory ids) {
        uint256[] storage all = posterPresenceIds[poster];
        uint256 len = all.length;
        if (start >= len || count == 0) {
            return new uint256[](0);
        }
        uint256 end = start + count;
        if (end > len) end = len;
        uint256 n = end - start;
        ids = new uint256[](n);
        for (uint256 i = 0; i < n; ) {
            ids[i] = all[start + i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Current number of live (not-yet-erased) Presence records.
     * @return live Live count.
     */
    function getLiveCount() external view returns (uint256 live) {
        live = liveCount;
    }

    /**
     * @notice Live effective (trust - push) for any wallet.
     * @param wallet Address to query.
     * @return result Signed effective value.
     */
    function currentEffective(address wallet) external view returns (int256 result) {
        result = _safeEffective(sos.balanceOf(wallet), sos.pushCountOf(wallet));
    }

    /**
     * @notice Convenience helper that unpacks the combined priceAndMethod field.
     * @param id The Presence id.
     * @return priceInReturn 5-byte price data.
     * @return method        Single-byte method code.
     */
    function getPriceAndMethod(uint256 id) external view returns (bytes5 priceInReturn, bytes1 method) {
        bytes6 packed = presences[id].priceAndMethod;
        method = bytes1(packed[0]);
        priceInReturn = bytes5(packed << 8);
    }

    /// @notice Rejects any plain ETH transfer.
    receive() external payable { revert("No ETH"); }

    /// @notice Rejects any call with non-matching calldata that also sends ETH.
    fallback() external payable { revert("No ETH"); }
}
