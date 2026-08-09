// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title SOS69069
 * @notice Pure forward mint contract with strict safety constraints and cyclic push count.
 *
 * COMPILER / ETHERSCAN VERIFICATION NOTES:
 * - This file targets Solidity ^0.8.35 (tested against solc 0.8.35 and 0.8.36).
 * - This contract has NO constructor arguments, so the "Constructor Arguments ABI-encoded"
 *   field on Etherscan should be left blank.
 * - This is a single file with no imports, so use Etherscan's "Solidity (Single file)"
 *   verification type, NOT "Solidity (Standard-Json-Input)" or "Multi-Part files".
 * - The #1 cause of "Unable to verify" / bytecode-mismatch errors on Etherscan is NOT
 *   the source code — it's a settings mismatch between what you deployed with and what
 *   you select on the verify form. Before verifying, confirm ALL of the following match
 *   exactly what your deploy tool (Remix, Foundry, Hardhat, etc.) actually used:
 *     1. Exact compiler version, including the commit hash (e.g. v0.8.35+commit.xxxxxxx).
 *        Selecting "0.8.35" from a dropdown that resolves to a different nightly/patch
 *        build will fail verification even though the source is identical.
 *     2. Optimization: enabled/disabled must match exactly.
 *     3. Optimization runs count must match exactly (e.g. 200 vs 1000000 gives different
 *        bytecode).
 *     4. EVM version must match (solc 0.8.30+ defaults to "prague", 0.8.35 still defaults
 *        to "prague" unless you explicitly overrode it at compile time — check your
 *        deploy config, don't assume "default").
 *     5. License identifier in the verify form should be MIT to match the SPDX line above.
 *   If any one of these differs from how the contract was actually compiled at deploy
 *   time, Etherscan will report a mismatch regardless of how correct the source is.
 *
 * SAFETY BLOCK:
 * - Exactly 1 wei (0.000000000000000001) token minted per call
 * - pushTo is the only mint function
 * - No mint to zero address
 * - No ETH accepted or held
 * - No transfers, approvals, burns, DEX logic, proxies, or ownable
 * - No selfdestruct
 *
 * CYCLE LOGIC (FOREVER RESTART):
 * - pushOf[user] wraps from type(uint256).max (2^256 - 1) to 0 forever
 * - trustOf[user] (balance) wraps from type(uint256).max (2^256 - 1) to 0 forever
 * - phase69069 (totalSupply) wraps from type(uint256).max (2^256 - 1) to 0 forever
 * - All three counters cycle independently, forever, with events emitted on overflow
 * - Overflow is detected with an explicit `== UINT256_MAX` guard BEFORE the addition
 *   runs, so the addition itself can never overflow. The addition is therefore wrapped
 *   in `unchecked { }` to skip Solidity's redundant automatic overflow check and save
 *   gas on every single pushTo() call. This changes gas cost only — not behavior.
 *
 * OVERFLOW TRACKING (PERMANENT, NON-CYCLIC):
 * - Every wrap event increments a permanent, on-chain overflow counter that never
 *   resets and is separate from the cyclic counters themselves
 * - pushOverflowCountOf(user)     — how many times user's pushOf has wrapped
 * - trustOverflowCountOf(account) — how many times account's trustOf has wrapped
 * - totalPhaseOverflowCount()     — how many times the contract-wide phase69069 has wrapped
 * - Readable at any time after deployment via public view functions
 *
 * TOKEN LOGIC (REAL FUNCTIONALITY):
 * - pushTo(to) mints 1 unit to recipient (to) — this is the only state-changing,
 *   value-bearing action in the contract
 * - trustOf[to] = balanceOf(to) (per-recipient balance from pushes received)
 * - phase69069 = totalSupply() (cyclic mint counter — NOT a guaranteed live sum of all
 *   balances; diverges from the real sum after any TrustOfOverflow event since each
 *   counter wraps independently. Use off-chain event indexing for the true balance sum.)
 * - pushOf[msg.sender] = how many times sender has called pushTo()
 *
 * ERC20-SHAPED SURFACE — DISPLAY/COMPATIBILITY ONLY, NOT REAL ERC20 FUNCTIONALITY:
 * This contract intentionally exposes a handful of function and event names that match
 * the ERC20 standard (name, symbol, decimals, balanceOf, totalSupply, Transfer) purely
 * so that wallets, explorers, and indexers can recognize and display SOS69069 as a
 * token and show push activity in a familiar "transfer history" UI.
 *   - name(), symbol(), decimals() are pure constants with NO underlying state — they
 *     exist only so wallet UIs render a name/symbol/decimal count instead of nothing.
 *   - balanceOf() and totalSupply() DO reflect real internal state (trustOf/phase69069),
 *     so these are not fake — they are real getters that also happen to satisfy the
 *     ERC20 read interface.
 *   - The Transfer event is emitted on every push SOLELY so wallets/explorers display
 *     the mint as "activity" in their standard token-transfer UI. It does NOT represent
 *     a real balance deduction: unlike a real ERC20 transfer, `trustOf[from]` is never
 *     decremented. Do not rely on Transfer logs to reconstruct sender balances — any
 *     tool that does so (a common indexing technique) will compute the wrong number,
 *     since no debit actually happens on-chain. There is no transfer(), approve(), or
 *     transferFrom() — the token cannot actually move between holders; it can only be
 *     minted via pushTo().
 *
 * SELF-PUSH:
 * - pushTo(msg.sender) is permitted. A caller may mint to themselves, incrementing
 *   both their own balance (trustOf) and their push count (pushOf). This is intentional.
 *
 * DECIMALS:
 * - decimals() returns 0
 * - Wallets and Etherscan natively display whole numbers: 1, 2, 3...
 * - 1 push = 1 unit displayed in wallet
 * - NOTE: changing this constant to 18 (the common ERC20 convention) would NOT change
 *   any push/mint logic, since decimals() is a pure display hint read independently
 *   of trustOf/pushOf/phase69069. However, standard wallets compute the human-readable
 *   balance as rawBalance / 10^decimals(). Since pushTo() always mints a raw amount of
 *   exactly 1, switching decimals() to 18 alone would make every wallet display a
 *   single push as 0.000000000000000001 — effectively invisible/near-zero — because
 *   the raw integer minted per push would not be scaled to match. Showing "normal"
 *   18-decimal-style balances (e.g. "1.0" per push) would require minting
 *   1e18 raw units per push instead of 1, which changes the internal integers (though
 *   not the conceptual one-push-one-unit design). This tradeoff is intentionally left
 *   unresolved here — see accompanying discussion.
 *
 * DISPLAY:
 * - displayBalanceOf() returns formatted string matching decimals() = 0
 * - Example: 1 push → "1", 10 pushes → "10"
 * - Internal math unchanged — display only
 * - This is a custom, non-ERC20 convenience function; it is NOT part of the standard
 *   ERC20 interface and exists only for callers who want a ready-to-print string
 *   instead of a raw uint256
 */

contract SOS69069 {

    // ==================== CONSTANTS ====================
    uint256 private constant EXACT_MINT_AMOUNT = 1;
    uint256 private constant UINT256_MAX = type(uint256).max;

    // ==================== INTERNAL STATE (REAL FUNCTIONALITY) ====================
    /// @dev How many times each address has called pushTo() as the sender (from).
    mapping(address => uint256) private pushOf;
    /// @dev Cyclic balance: how many units each address has received via pushTo().
    mapping(address => uint256) private trustOf;
    /// @dev Cyclic contract-wide mint counter (see totalSupply()).
    uint256 private phase69069;

    // ==================== OVERFLOW COUNTERS (PERMANENT, NON-CYCLIC) ====================
    /// @dev Permanent count of how many times each address's pushOf has wrapped.
    mapping(address => uint256) private pushOverflowCount;
    /// @dev Permanent count of how many times each address's trustOf has wrapped.
    mapping(address => uint256) private trustOverflowCount;
    /// @dev Permanent count of how many times phase69069 has wrapped, contract-wide.
    uint256 private phaseOverflowCount;

    // ==================== EVENTS ====================
    /// @notice Real event: emitted on every pushTo(), the contract's only mint action.
    event Pushed(address indexed from, address indexed to, uint256 amount);
    /// @notice ERC20-COMPATIBILITY EVENT ONLY. Emitted so wallets/explorers show push
    /// activity as a familiar "transfer". Does NOT represent a real balance deduction
    /// from `from` — trustOf[from] is never decremented. Do not treat this as proof of
    /// a debit; use Pushed (or trustOf/pushOf directly) for anything that must reflect
    /// real state.
    event Transfer(address indexed from, address indexed to, uint256 value);
    /// @notice Real event: fired when an address's pushOf wraps from UINT256_MAX to 0.
    event PushOverflow(address indexed user, uint256 prevPushOf);
    /// @notice Real event: fired when an address's trustOf wraps from UINT256_MAX to 0.
    event TrustOfOverflow(address indexed account, uint256 prevBalance);
    /// @notice Real event: fired when the contract-wide phase69069 wraps to 0.
    event PhaseOverflow(uint256 prevTotalSupply);

    // ==================== ERRORS ====================
    error NoETHAccepted();
    error PushToZeroAddress();

    // ==================== VIEW FUNCTIONS ====================

    /// @notice ERC20-COMPATIBILITY ONLY. Pure constant, no underlying state; exists so
    /// wallets/explorers display a name instead of nothing.
    function name() public pure returns (string memory) {
        return "69069";
    }

    /// @notice ERC20-COMPATIBILITY ONLY. Pure constant, no underlying state.
    function symbol() public pure returns (string memory) {
        return "SOS";
    }

    /// @notice ERC20-COMPATIBILITY ONLY. Pure constant, no underlying state. See the
    /// DECIMALS note in the contract header for the tradeoffs of changing this.
    function decimals() public pure returns (uint8) {
        return 0;
    }

    /// @notice REAL FUNCTIONALITY. Returns the cyclic, contract-wide mint counter.
    /// Also exposed identically via verifyTotalSupply() below — see that function's
    /// docstring for why both exist.
    function totalSupply() public view returns (uint256) {
        return phase69069;
    }

    /// @notice REAL FUNCTIONALITY. Returns `account`'s real cyclic balance (trustOf).
    /// Satisfies the ERC20 read interface but reflects genuine on-chain state.
    function balanceOf(address account) public view returns (uint256) {
        return trustOf[account];
    }

    /// @notice REAL FUNCTIONALITY. Returns how many times `user` has called pushTo().
    function pushCountOf(address user) public view returns (uint256) {
        return pushOf[user];
    }

    /// @notice CONVENIENCE ALIAS. Identical result to pushCountOf(msg.sender); no
    /// separate storage or logic — kept as a no-argument shortcut for the caller.
    function myPushCount() public view returns (uint256) {
        return pushOf[msg.sender];
    }

    /// @notice CONVENIENCE ALIAS. Identical result to balanceOf(msg.sender).
    function myBalance() public view returns (uint256) {
        return trustOf[msg.sender];
    }

    /// @notice DUPLICATE OF totalSupply(). Returns the exact same value via the exact
    /// same storage read. Kept intentionally as-is (contract logic preserved
    /// unchanged) — if you don't need a separately named getter, this can be removed
    /// with zero functional impact, since totalSupply() already provides the value.
    function verifyTotalSupply() public view returns (uint256 storedTotal) {
        storedTotal = phase69069;
    }

    /// @notice Utility constant getter — returns type(uint256).max for off-chain
    /// convenience (e.g. so a frontend doesn't have to hardcode the wrap threshold).
    function uint256Max() public pure returns (uint256) {
        return type(uint256).max;
    }

    // ==================== OVERFLOW COUNT VIEW FUNCTIONS ====================

    /// @notice REAL FUNCTIONALITY. How many times `user`'s pushOf counter has wrapped
    /// from UINT256_MAX to 0. Permanent — never itself resets.
    function pushOverflowCountOf(address user) public view returns (uint256) {
        return pushOverflowCount[user];
    }

    /// @notice REAL FUNCTIONALITY. How many times `account`'s trustOf (balance)
    /// counter has wrapped from UINT256_MAX to 0. Permanent — never itself resets.
    function trustOverflowCountOf(address account) public view returns (uint256) {
        return trustOverflowCount[account];
    }

    /// @notice CONVENIENCE ALIAS. Identical result to pushOverflowCountOf(msg.sender).
    function myPushOverflowCount() public view returns (uint256) {
        return pushOverflowCount[msg.sender];
    }

    /// @notice CONVENIENCE ALIAS. Identical result to trustOverflowCountOf(msg.sender).
    function myTrustOverflowCount() public view returns (uint256) {
        return trustOverflowCount[msg.sender];
    }

    /// @notice REAL FUNCTIONALITY. How many times the contract-wide phase69069
    /// (totalSupply) counter has wrapped. Permanent — never itself resets.
    function totalPhaseOverflowCount() public view returns (uint256) {
        return phaseOverflowCount;
    }

    // ==================== DISPLAY VIEW (NON-ERC20 CONVENIENCE, NOT STANDARD) ====================

    /// @notice NOT part of the ERC20 standard. Formats `account`'s real trustOf
    /// balance as a plain decimal string matching decimals() = 0 (e.g. "1", "10").
    /// Pure convenience for callers that want a ready-to-print string.
    function displayBalanceOf(address account) public view returns (string memory) {
        return _uintToString(trustOf[account]);
    }

    /// @notice CONVENIENCE ALIAS. Identical result to displayBalanceOf(msg.sender).
    function myDisplayBalance() public view returns (string memory) {
        return _uintToString(trustOf[msg.sender]);
    }

    /// @dev Internal string-formatting helper. No state read/written beyond the
    /// `value` passed in; pure integer-to-ASCII conversion.
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ==================== INTERNAL MINT LOGIC (REAL FUNCTIONALITY) ====================

    /// @dev Core state-changing logic shared by pushTo() and pushForMe(). For each of
    /// the three cyclic counters (pushOf[from], trustOf[to], phase69069):
    ///   1. Read the current value once (single SLOAD).
    ///   2. If it's already at UINT256_MAX, wrapping is guaranteed safe: emit the
    ///      matching overflow event, reset the counter to 0, and increment its
    ///      permanent (non-cyclic) overflow counter.
    ///   3. Otherwise, add EXACT_MINT_AMOUNT (1). Because branch (2) already proved
    ///      current != UINT256_MAX whenever this branch runs, the addition can never
    ///      overflow — so it's wrapped in `unchecked { }` to skip Solidity's automatic
    ///      overflow check and save gas on every pushTo(). This is a gas-only change:
    ///      the guard above makes the result identical to the checked version.
    /// Finally emits Pushed (real) and Transfer (ERC20-compatibility only, see event
    /// docstring above) to record the mint.
    function _push(address from, address to) internal {
        uint256 currentPush  = pushOf[from];
        uint256 currentTrust = trustOf[to];
        uint256 currentPhase = phase69069;

        if (currentPush == UINT256_MAX) {
            emit PushOverflow(from, UINT256_MAX);
            pushOf[from] = 0;
            pushOverflowCount[from] += 1;
        } else {
            unchecked {
                pushOf[from] = currentPush + EXACT_MINT_AMOUNT;
            }
        }

        if (currentTrust == UINT256_MAX) {
            emit TrustOfOverflow(to, UINT256_MAX);
            trustOf[to] = 0;
            trustOverflowCount[to] += 1;
        } else {
            unchecked {
                trustOf[to] = currentTrust + EXACT_MINT_AMOUNT;
            }
        }

        if (currentPhase == UINT256_MAX) {
            emit PhaseOverflow(UINT256_MAX);
            phase69069 = 0;
            phaseOverflowCount += 1;
        } else {
            unchecked {
                phase69069 = currentPhase + EXACT_MINT_AMOUNT;
            }
        }

        emit Pushed(from, to, EXACT_MINT_AMOUNT);
        emit Transfer(from, to, EXACT_MINT_AMOUNT);
    }

    // ==================== PUSHTO - ONLY MINT FUNCTION (REAL FUNCTIONALITY) ====================

    /// @notice The contract's sole mint entry point. Mints exactly 1 unit to `to`.
    /// Reverts if `to` is the zero address. `external` (not `public`) since it is
    /// never called internally, which avoids the extra ABI-decode overhead `public`
    /// functions pay when called externally.
    /// @custom:display Push
    function pushTo(address to) external {
        if (to == address(0)) revert PushToZeroAddress();
        _push(msg.sender, to);
    }

    // ==================== PUSHFORME (REAL FUNCTIONALITY) ====================

    /// @notice Convenience wrapper that self-pushes: mints 1 unit to msg.sender.
    /// No zero-address check needed — msg.sender can never be address(0) in a call.
    /// @custom:display Push for Me
    function pushForMe() external {
        _push(msg.sender, msg.sender);
    }

    /// @notice Rejects any plain ETH transfer with no calldata. The contract never
    /// accepts or holds ETH.
    receive() external payable { revert NoETHAccepted(); }

    /// @notice Rejects any call with unrecognized calldata or attached ETH.
    fallback() external payable { revert NoETHAccepted(); }
}

/*
================================================================================
 SOS69069 — DOCUMENTATION
================================================================================

Pure forward mint contract with strict safety constraints and infinite cyclic counters.

SOS69069 is a minimal token minting contract where exactly 1 unit is minted per
pushTo() call. All three core counters cycle forever when they reach 2^256 - 1,
wrapping back to 0 with overflow events emitted. Every wrap also increments a
permanent, non-cyclic overflow counter that can be read at any time after
deployment, per address or contract-wide.

================================================================================
 REAL FUNCTIONALITY vs ERC20-COMPATIBILITY-ONLY SURFACE
================================================================================

REAL (backed by actual contract state / state changes):
  pushTo(address)              — the only mint function
  pushForMe()                 — self-push convenience
  balanceOf(address)          — real trustOf balance
  totalSupply()               — real phase69069 counter
  pushCountOf(address)        — real pushOf counter
  pushOverflowCountOf(address), trustOverflowCountOf(address),
    totalPhaseOverflowCount() — real, permanent overflow counters
  Pushed, PushOverflow, TrustOfOverflow, PhaseOverflow — real events

ERC20-SHAPED, DISPLAY/COMPATIBILITY ONLY:
  name(), symbol(), decimals() — constants with no state, exist purely so
    wallets/explorers render a token name/symbol/decimals instead of nothing
  Transfer event — emitted only so wallet/explorer UIs show push activity as
    "transfer history"; does NOT represent a real debit from the sender

CONVENIENCE ALIASES (identical result to calling the address-parameterized
version with msg.sender — no separate state or logic):
  myPushCount(), myBalance(), myDisplayBalance(),
  myPushOverflowCount(), myTrustOverflowCount()

DUPLICATE:
  verifyTotalSupply() returns the exact same value as totalSupply() via the
  exact same storage read. Kept as-is; contract logic unchanged.

NOT PART OF ERC20 STANDARD (custom convenience, no transfer()/approve() exist):
  displayBalanceOf(address), myDisplayBalance()

================================================================================
 SAFETY BLOCK
================================================================================

- Exactly 1 unit minted per pushTo() call
- pushTo() is the ONLY mint function
- No mint to zero address
- No ETH accepted or held
- No transfers, approvals, burns, DEX logic, proxies, or ownable
- No selfdestruct
- Token cannot actually move between holders post-mint: no transfer()/approve()/
  transferFrom() exist, despite the Transfer event and balanceOf()/totalSupply()
  compatibility surface

================================================================================
 CYCLE LOGIC (FOREVER RESTART)
================================================================================

All counters wrap from 2^256 - 1 to 0 forever:

  pushOf[user]   — how many times user called pushTo()     → event PushOverflow
  trustOf[to]    — balance = balanceOf(to)               → event TrustOfOverflow
  phase69069     — totalSupply()                         → event PhaseOverflow

Overflow value: 2^256 - 1 = 115792089237316195423570985008687907853269984665640564039457584007913129639935

Each guarded addition in _push() runs inside `unchecked { }` — safe only because
the code has already proven (via the `== UINT256_MAX` check immediately above it)
that the addition cannot overflow. This is a gas optimization with no behavior
change: Solidity's default overflow check on that specific `+` would always pass
anyway, so skipping it removes wasted gas without altering results.

================================================================================
 OVERFLOW TRACKING (PERMANENT, NON-CYCLIC)
================================================================================

Each time a cyclic counter wraps, a separate permanent counter is incremented.
These permanent counters never wrap themselves and are readable at any time
after deployment:

  pushOverflowCountOf(address user)      — times user's pushOf has wrapped
  trustOverflowCountOf(address account)  — times account's trustOf has wrapped
  myPushOverflowCount()                  — caller's own pushOf wrap count
  myTrustOverflowCount()                 — caller's own trustOf wrap count
  totalPhaseOverflowCount()              — times the contract-wide phase69069 has wrapped

================================================================================
 FUNCTIONS
================================================================================

  function name()                        public pure returns (string memory)   // "69069" — display only
  function symbol()                      public pure returns (string memory)   // "SOS"   — display only
  function decimals()                    public pure returns (uint8)           // 0       — display only
  function totalSupply()                 public view returns (uint256)         // phase69069 (real)
  function balanceOf(address)            public view returns (uint256)         // trustOf[account] (real)
  function pushCountOf(address)          public view returns (uint256)         // pushOf[user] (real)
  function myPushCount()                 public view returns (uint256)         // alias
  function myBalance()                   public view returns (uint256)         // alias
  function verifyTotalSupply()           public view returns (uint256)         // duplicate of totalSupply()
  function pushOverflowCountOf(address)  public view returns (uint256)         // real, permanent
  function trustOverflowCountOf(address) public view returns (uint256)         // real, permanent
  function myPushOverflowCount()         public view returns (uint256)         // alias
  function myTrustOverflowCount()        public view returns (uint256)         // alias
  function totalPhaseOverflowCount()     public view returns (uint256)         // real, permanent, contract-wide
  function displayBalanceOf(address)     public view returns (string memory)   // non-standard, formatting only
  function myDisplayBalance()            public view returns (string memory)   // alias, non-standard
  function pushForMe()                   external                              // self-push convenience
  function pushTo(address to)              external                              // mint 1 to recipient — the only real mint

================================================================================
 EVENTS
================================================================================

  event Pushed(address indexed from, address indexed to, uint256 amount);        // real
  event Transfer(address indexed from, address indexed to, uint256 value);       // ERC20-compatibility display only
  event PushOverflow(address indexed user, uint256 prevPushOf);                  // real
  event TrustOfOverflow(address indexed account, uint256 prevBalance);           // real
  event PhaseOverflow(uint256 prevTotalSupply);                                  // real

================================================================================
 ERRORS
================================================================================

  error NoETHAccepted();
  error PushToZeroAddress();

================================================================================
HOW THE 69069 CONTRACT WORKS ?
================================================================================

## Overview

The SOS 69069 contract is built on three core concepts:

1. **Authority of One License**
2. **Anti-Speculation Safeguard**
3. **SOSAIXONE Numeric System**

These are complemented by the mint model (Sovereign vs. Non-Sovereign), a recovery procedure, and the underlying philosophy of the SOS Sovereign Legacy Field.

---

## 1. Authority of One License

The Authority of One License is established through a symbolic mint of **1 unit SOS** to the creator address.

**Creator address:**
`0x1C10e6574ee696f54b21A611a21313E4714628ad`

- New users are considered full-right members once they mint 1 unit to the creator address.
- By minting to the creator address, the user agrees to the rules encoded in the SOS token contract.
- Users should keep a record of their atomic 1-unit mint event to the creator address, as this record may be referenced by anyone using data generated by the SOS 69069 contract.

---

## 2. Anti-Speculation Safeguard

The Anti-Speculation Safeguard is a core safety principle to apply to any address a user interacts with:

- **Verify minting status:** Check whether the address in question has minted to the creator address.
- **Favor trust diversity:** Prefer interacting with users whose `trustOf` originates from many diverse sources rather than from a small number of users.
- **Trust-to-push ratio:** `trustOf(address)` must always be greater than `pushCountOf(address)`. If this condition is not met for a given address, exercise caution before interacting with it.

NOTE: this safeguard is a social/off-chain convention only — nothing in the contract
enforces it. See prior exploit review for details.

---

## 3. SOSAIXONE Numeric System

SOSAIXONE is a geometric alphanumeric system based on the symbol **O** (big O):

- **Digits 1–8:** a big O with a dash crossing it at one of eight positions around the circle.
- **Digit 9:** a big O with a small "o" inside it.
- **Digit 0:** a big O with a dot inside it.

**SOS 69069 logo:** [View logo](https://drive.google.com/file/d/1U6KZQXX3ttZOJMgjW97JgN0gWd6ndJEQ/view?usp=drivesdk)

---

## 4. Trust Of and Push Of — Sovereign Minting

Mint events are classified into two categories:

### Non-Sovereign Mint
- Any mint to your address where **another user** pays the gas cost.
- Any mint you perform to another address where **they** pay the gas cost.

### Sovereign Mint
- Any mint to your address where **you** pay the gas cost.
- Any mint you perform to another address where **you** pay the gas cost.

---

## 5. Recovery Procedure — Quick Steps

If access to a key is lost, recovery follows a purely on-chain process:

1. **Create a new address.**
2. **Initiate recovery:** From the new address, send the first push to the old address. This links the new address to the old one and starts the recovery process.
3. **Build activity:** Continue pushing from the new address until its push count reaches **2×** the total push count of the old address.
4. **Completion:** Once the 2× threshold is reached, the new address inherits the full history of the old address, and identity carries forward.

There is no password, company, deadline, or third party involved — the entire process runs on-chain and is verifiable through push activity alone.

NOTE: this recovery procedure is a social/off-chain convention only — the contract
has no concept of "recovery" or address linkage. See prior exploit review for details.

---

## SOS Sovereign Legacy Field

### I. Core Structure

The SOS Sovereign Legacy Field is a system of independent actors connected solely through a shared record of participation.

- Each actor is fully autonomous and self-determined.
- No actor holds ownership, governance, or definitional authority over the system.
- The system exists exclusively by virtue of participation.

**Structure:**
`Independent Sovereign Actors + Recorded Participation = Legacy Field`

### II. The Legacy Field (L)

Let **L** denote the Sovereign Legacy Field.

- L is a cumulative record of participation events.
- L does not retain identity, status, or authority.
- L records only the occurrence of actions.

Each action contributes to a continuous historical layer:

`Action → Event → Accumulation → Legacy Formation`

Accordingly, L constitutes a record of activity, not of persons.

### III. Sovereign Independence Principle

Each participant:

- Exercises exclusive control over their own actions.
- Possesses no authority to define, alter, or govern other participants.
- Enters the system solely through voluntary participation.
- Retains full and inalienable sovereignty at all times.

Sovereignty is non-transferable and not subject to external modification.

### IV. System Characterization

The SOS Sovereign Legacy Field is defined by the following properties:

- A network without ownership.
- A structure without governance hierarchy.
- A record without identity attribution.
- An emergent system constituted solely through participation over time.
================================================================================
*/
