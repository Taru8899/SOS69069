// ── constants ──
const CREATOR_ADDRESS = "0x1C10e6574ee696f54b21A611a21313E4714628ad";

let walletAddress = "";

const connectButton = document.getElementById("connectButton");
const mintButton = document.getElementById("mintButton");

mintButton.disabled = true;

// ── connect wallet ──
connectButton.onclick = async function () {
    try {
        document.getElementById("status").innerText = "Connecting…";

        walletAddress = await connectWallet();

        document.getElementById("address").innerText = walletAddress;

        // Pre‑fill the receiver field with the creator address
        const receiverInput = document.getElementById("receiver");
        if (receiverInput) {
            receiverInput.value = CREATOR_ADDRESS;
        }

        await refreshWallet();

        mintButton.disabled = false;

        document.getElementById("status").innerText = "Connected";
    } catch (err) {
        console.error(err);
        document.getElementById("status").innerText = err.message;
    }
};

// ── refresh balance / supply ──
async function refreshWallet() {
    console.log("Loading SOS data");
    console.log("Contract:", contract);
    console.log("Current wallet:", walletAddress);

    const trust = await getTrust(walletAddress);
    const push = await getPushCount(walletAddress);
    const total = await getTotalSupply();

    document.getElementById("trust").innerText = trust.toString();
    document.getElementById("push").innerText = push.toString();
    document.getElementById("effective").innerText = (BigInt(trust) - BigInt(push)).toString();
    document.getElementById("totalSupply").innerText = total.toString();
}

// ── mint handler ──
mintButton.onclick = async function () {
    const progressEl = document.getElementById("mintProgress");
    const receiverRaw = document.getElementById("receiver").value.trim();
    const n = parseInt(document.getElementById("mintCount").value, 10) || 1;

    // If the field is empty → treat as "mint to yourself"
    const isSelf = !receiverRaw ||
        (walletAddress && receiverRaw.toLowerCase() === walletAddress.toLowerCase());

    const receiver = isSelf ? null : receiverRaw;

    if (!isSelf) {
        if (!/^0x[a-fA-F0-9]{40}$/.test(receiver)) {
            alert("Enter a valid Ethereum address (0x…) or leave blank to mint to yourself.");
            return;
        }
    }

    if (n < 1) {
        alert("Enter how many SOS to mint (1 or more).");
        return;
    }

    if (n > 50) {
        alert("Max 50 per batch — that's already 50 separate wallet confirmations.");
        return;
    }

    if (n > 5) {
        const ok = confirm(
            "This will ask you to confirm " + n + " separate wallet transactions, one at a time, " +
            "and each one costs its own gas fee. Continue?"
        );
        if (!ok) return;
    }

    mintButton.disabled = true;
    let completed = 0;

    for (let i = 1; i <= n; i++) {
        if (n === 1) {
            document.getElementById("status").innerText = "Waiting for wallet confirmation…";
            progressEl.innerText = "";
        } else {
            progressEl.innerText = "Minting " + i + " of " + n + "… confirm in your wallet";
            document.getElementById("status").innerText = "Minting " + i + " of " + n + "…";
        }

        try {
            if (isSelf) {
                await pushForMe();
            } else {
                await pushTo(receiver);
            }

            completed++;

            if (n > 1) {
                progressEl.innerText = completed + " of " + n + " confirmed ✓";
            }

            await refreshWallet();
        } catch (err) {
            console.error(err);

            const msg = err.shortMessage || err.message;

            if (n > 1) {
                progressEl.innerText =
                    "Stopped after " + completed + " of " + n + " — " + msg;
                document.getElementById("status").innerText =
                    "Batch mint stopped: " + msg;
            } else {
                document.getElementById("status").innerText = msg;
                progressEl.innerText = "";
            }

            mintButton.disabled = false;
            return;
        }
    }

    if (n === 1) {
        document.getElementById("status").innerText =
            isSelf ? "Self Push Successful" : "Mint Successful";
        progressEl.innerText = "";
    } else {
        document.getElementById("status").innerText =
            "Batch mint complete — " + completed + " SOS minted";
    }

    mintButton.disabled = false;
};
