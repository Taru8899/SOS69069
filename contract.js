// ===============================
// SOS69069 Ethereum Mainnet Wallet
// ===============================


const SOS_CONTRACT =
"0x61af906f53Eb927790055AC8eA99916a01873c15";


const ETH_CHAIN_ID = 1n;


// Minimal ABI

const SOS_ABI = [

{
    "inputs":[
        {
            "internalType":"address",
            "name":"account",
            "type":"address"
        }
    ],
    "name":"balanceOf",
    "outputs":[
        {
            "internalType":"uint256",
            "name":"",
            "type":"uint256"
        }
    ],
    "stateMutability":"view",
    "type":"function"
},


{
    "inputs":[
        {
            "internalType":"address",
            "name":"user",
            "type":"address"
        }
    ],
    "name":"pushCountOf",
    "outputs":[
        {
            "internalType":"uint256",
            "name":"",
            "type":"uint256"
        }
    ],
    "stateMutability":"view",
    "type":"function"
},


{
    "inputs":[],
    "name":"totalSupply",
    "outputs":[
        {
            "internalType":"uint256",
            "name":"",
            "type":"uint256"
        }
    ],
    "stateMutability":"view",
    "type":"function"
},


{
    "inputs":[
        {
            "internalType":"address",
            "name":"to",
            "type":"address"
        }
    ],
    "name":"pushTo",
    "outputs":[],
    "stateMutability":"nonpayable",
    "type":"function"
},


{
    "inputs":[],
    "name":"pushForMe",
    "outputs":[],
    "stateMutability":"nonpayable",
    "type":"function"
}

];



// ===============================
// GLOBAL VARIABLES
// ===============================


let provider = null;
let signer = null;
let contract = null;

// Read-only fallback: lets trust/push/effective/totalSupply load
// even before MetaMask is connected (or if it's locked/unavailable).
// View calls don't need a signer, only transactions do.
const READ_RPC_URL = "https://cloudflare-eth.com";
let readProvider = null;
let readContract = null;

function getReadContract(){
    if(!readContract){
        readProvider = new ethers.JsonRpcProvider(READ_RPC_URL);
        readContract = new ethers.Contract(
            SOS_CONTRACT,
            SOS_ABI,
            readProvider
        );
    }
    return readContract;
}



// ===============================
// FORCE ETHEREUM MAINNET
// ===============================


async function switchToEthereum(injected){


    const current =
    await injected.request({

        method:"eth_chainId"

    });


    console.log(
        "Current chain:",
        current
    );


    if(current !== "0x1"){


        await injected.request({

            method:"wallet_switchEthereumChain",

            params:[
                {
                    chainId:"0x1"
                }
            ]

        });

    }

}



// ===============================
// CONNECT WALLET
// ===============================


function getInjectedProvider(){

    if(!window.ethereum){
        return null;
    }

    // Some wallet browsers/extensions inject multiple providers
    // into window.ethereum.providers when more than one wallet
    // is installed. Fall back to that list if the top-level
    // window.ethereum object itself isn't usable.
    if(
        Array.isArray(window.ethereum.providers) &&
        window.ethereum.providers.length > 0
    ){

        return window.ethereum.providers[0];

    }

    return window.ethereum;

}


async function connectWallet(){


    const injected = getInjectedProvider();

    if(!injected){

        throw new Error(
            "No Ethereum wallet found. Open this page inside your wallet's browser, or install a wallet extension (MetaMask, TokenPocket, Trust Wallet, Rabby, Coinbase Wallet, etc.)."
        );

    }



    // IMPORTANT
    // switch BEFORE creating provider

    await switchToEthereum(injected);



    provider =
    new ethers.BrowserProvider(
        injected
    );



    await provider.send(
        "eth_requestAccounts",
        []
    );



    const network =
    await provider.getNetwork();



    console.log(
        "Network ID:",
        network.chainId.toString()
    );



    if(network.chainId !== ETH_CHAIN_ID){

        throw new Error(
            "Wrong network. Ethereum Mainnet required."
        );

    }



    // Check contract exists

    const code =
    await provider.getCode(
        SOS_CONTRACT
    );



    console.log(
        "Contract bytecode:",
        code
    );



    if(code === "0x"){


        throw new Error(
            "SOS69069 contract not found on Ethereum Mainnet"
        );


    }



    signer =
    await provider.getSigner();



    contract =
    new ethers.Contract(

        SOS_CONTRACT,

        SOS_ABI,

        signer

    );



    console.log(
        "SOS69069 connected"
    );



    return await signer.getAddress();


}



// ===============================
// READ FUNCTIONS
// ===============================


async function getTrust(address){


    const c = contract || getReadContract();

    const result =
    await c.balanceOf(
        address
    );


    return result;


}



async function getPushCount(address){


    const c = contract || getReadContract();

    const result =
    await c.pushCountOf(
        address
    );


    return result;


}



async function getTotalSupply(){


    const c = contract || getReadContract();

    const result =
    await c.totalSupply();


    return result;


}



// ===============================
// MINT TO ADDRESS
// ===============================


async function pushTo(receiver){


    if(!provider || !contract){

        throw new Error(
            "Connect your wallet first."
        );

    }



    const network =
    await provider.getNetwork();



    if(network.chainId !== ETH_CHAIN_ID){

        throw new Error(
            "Ethereum Mainnet required"
        );

    }



    console.log(
        "Minting to:",
        receiver
    );



    const tx =
    await contract.pushTo(
        receiver
    );



    console.log(
        "TX HASH:",
        tx.hash
    );



    const receipt =
    await tx.wait();



    console.log(
        "CONFIRMED:",
        receipt
    );



    return receipt;


}



// ===============================
// SELF MINT
// ===============================


async function pushForMe(){


    if(!provider || !contract){

        throw new Error(
            "Connect your wallet first."
        );

    }



    const network =
    await provider.getNetwork();



    if(network.chainId !== ETH_CHAIN_ID){

        throw new Error(
            "Ethereum Mainnet required"
        );

    }



    const tx =
    await contract.pushForMe();



    console.log(
        "TX HASH:",
        tx.hash
    );



    return await tx.wait();


}



// ===============================
// NETWORK CHANGE LISTENER
// ===============================


if(window.ethereum){


    window.ethereum.on(

        "chainChanged",

        function(chainId){


            console.log(
                "Chain changed:",
                chainId
            );


            window.location.reload();


        }

    );


}


// ===============================
// EXPOSE FUNCTIONS TO GLOBAL SCOPE
// ===============================

// Make all functions available globally for legacy.html and other pages
window.connectWallet = connectWallet;
window.getTrust = getTrust;
window.getPushCount = getPushCount;
window.getTotalSupply = getTotalSupply;
window.pushTo = pushTo;
window.pushForMe = pushForMe;
window.switchToEthereum = switchToEthereum;
window.getInjectedProvider = getInjectedProvider;
window.getReadContract = getReadContract;

console.log('✅ SOS69069 contract functions exposed to window');


// ===============================
// WALLETCONNECT SUPPORT
// ===============================
// Added to support WalletConnect and Deep Links connection methods
// This preserves all existing functionality while adding
// WalletConnect compatibility for mobile users

// These will be set by index.html when WalletConnect connects
window.wcSigner = null;
window.wcContract = null;
window.isWcConnected = false;

// Store original functions before overriding
const _originalConnectWallet = window.connectWallet;
const _originalPushTo = window.pushTo;
const _originalPushForMe = window.pushForMe;

// Enhanced connect function - tries WalletConnect first, then falls back to extension
window.connectWallet = async function() {
    // Try WalletConnect first if available
    if (window.isWcConnected && window.wcSigner) {
        console.log("✅ Using WalletConnect for connection");
        return await window.wcSigner.getAddress();
    }
    // Fall back to original browser wallet connection
    if (_originalConnectWallet) {
        console.log("✅ Using browser extension for connection");
        return await _originalConnectWallet();
    }
    throw new Error("No wallet available. Please connect via MetaMask or WalletConnect.");
};

// Enhanced pushTo - tries WalletConnect first, then falls back to extension
window.pushTo = async function(receiver) {
    // Try WalletConnect first if available
    if (window.isWcConnected && window.wcContract) {
        console.log("✅ Using WalletConnect for pushTo");
        const tx = await window.wcContract.pushTo(receiver);
        console.log("📝 TX HASH:", tx.hash);
        return await tx.wait();
    }
    // Fall back to original browser wallet
    if (_originalPushTo) {
        console.log("✅ Using browser extension for pushTo");
        return await _originalPushTo(receiver);
    }
    throw new Error("No wallet available. Please connect via MetaMask or WalletConnect.");
};

// Enhanced pushForMe - tries WalletConnect first, then falls back to extension
window.pushForMe = async function() {
    // Try WalletConnect first if available
    if (window.isWcConnected && window.wcContract) {
        console.log("✅ Using WalletConnect for pushForMe");
        const tx = await window.wcContract.pushForMe();
        console.log("📝 TX HASH:", tx.hash);
        return await tx.wait();
    }
    // Fall back to original browser wallet
    if (_originalPushForMe) {
        console.log("✅ Using browser extension for pushForMe");
        return await _originalPushForMe();
    }
    throw new Error("No wallet available. Please connect via MetaMask or WalletConnect.");
};

console.log('✅ WalletConnect support added to contract.js');
