// Turn by Turn — frontend. ethers v6, no build step.
// Contract address is injected after deploy into this file as CONTRACT.
const CONTRACT = "0x8621067F8de51DEE4E215a6A9F7E668C0333cD7C"; // Base Sepolia
const CHAIN_ID = 84532n; // Base Sepolia
const RPC = "https://sepolia.base.org";
const EXPLORER = "https://sepolia.basescan.org";

const ABI = [
  "function createGame() returns (uint256)",
  "function joinGame(uint256 gameId)",
  "function cancelGame(uint256 gameId)",
  "function play(uint256 gameId, uint8 col)",
  "function claimTimeout(uint256 gameId)",
  "function gamesCount() view returns (uint256)",
  "function gamesOf(address) view returns (uint256[])",
  "function openGames(uint256 maxResults) view returns (uint256[])",
  "function boardOf(uint256 gameId) view returns (uint8[])",
  "function games(uint256) view returns (address player1, address player2, address turn, address winner, uint8 status, uint64 lastMoveAt, uint8 moves)",
  "event GameCreated(uint256 indexed gameId, address indexed player1)",
  "event GameJoined(uint256 indexed gameId, address indexed player2)",
  "event MovePlayed(uint256 indexed gameId, address indexed player, uint8 col, uint8 row)",
  "event GameWon(uint256 indexed gameId, address indexed winner, string reason)",
  "event GameDrawn(uint256 indexed gameId)",
];
const STATUS = ["Open", "Active", "Finished", "Cancelled"];
const TIMEOUT = 3 * 24 * 3600;

let provider, signer, me, contract, currentGame = null;

const $ = (id) => document.getElementById(id);
const log = (m) => {
  const el = $("log");
  el.textContent = `[${new Date().toLocaleTimeString()}] ${m}\n` + el.textContent;
};
const short = (a) => a ? a.slice(0, 6) + "…" + a.slice(-4) : "—";

async function init() {
  // read-only provider always works (view games without a wallet)
  provider = new ethers.BrowserProvider(window.ethereum || undefined);
  if (!window.ethereum) {
    provider = new ethers.JsonRpcProvider(RPC);
    log("No wallet found — read-only mode.");
  }
  contract = new ethers.Contract(CONTRACT, ABI, provider);
  await refreshLists();
  setInterval(refreshLists, 20000);
  if (currentGame !== null) renderGame(currentGame);
}

async function connect() {
  if (!window.ethereum) { log("Install a wallet (Rabby/MetaMask) to play."); return; }
  provider = new ethers.BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  const net = await provider.getNetwork();
  if (net.chainId !== CHAIN_ID) {
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0x14a34" }],
      });
    } catch (e) {
      if (e.code === 4902) {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: "0x14a34", chainName: "Base Sepolia",
            rpcUrls: [RPC], nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
            blockExplorerUrls: [EXPLORER],
          }],
        });
      } else { log("Network switch failed: " + e.message); return; }
    }
    provider = new ethers.BrowserProvider(window.ethereum);
  }
  signer = await provider.getSigner();
  me = await signer.getAddress();
  contract = new ethers.Contract(CONTRACT, ABI, signer);
  $("me").innerHTML = `You: <b>${short(me)}</b> <span class="pill on">connected</span>`;
  $("connectBtn").disabled = true;
  $("newGameBtn").disabled = false;
  log("Connected " + me);
  await refreshLists();
  if (currentGame !== null) renderGame(currentGame);
}

async function refreshLists() {
  try {
    const open = await contract.openGames(20);
    const box = $("openGames");
    if (open.length === 0) { box.innerHTML = '<span class="muted">No open games — create one.</span>'; }
    else {
      box.innerHTML = "";
      for (const id of open) {
        const g = await contract.games(id);
        const d = document.createElement("div");
        d.className = "gameitem";
        d.innerHTML = `Game #${id} — by ${short(g.player0 ?? g[0])} <button style="float:right;padding:3px 10px;font-size:12px">Join</button>`;
        d.onclick = () => joinGame(id);
        box.appendChild(d);
      }
    }
    if (me) {
      const mine = await contract.gamesOf(me);
      const mb = $("myGames");
      mb.innerHTML = mine.length ? "<h3 style='margin-top:14px;font-size:14px'>Your games</h3>" : "";
      for (const id of mine.slice().reverse()) {
        const g = await contract.games(id);
        const st = STATUS[g[4]];
        const d = document.createElement("div");
        d.className = "gameitem";
        const turnMark = (st === "Active" && g[2].toLowerCase() === me.toLowerCase()) ? " — <b style='color:var(--green)'>your turn</b>" : "";
        d.innerHTML = `Game #${id} — ${st}${turnMark}`;
        d.onclick = () => renderGame(Number(id));
        mb.appendChild(d);
      }
    }
  } catch (e) { log("refresh: " + (e.shortMessage || e.message)); }
}

async function renderGame(id) {
  currentGame = id;
  const g = await contract.games(id);
  const board = await contract.boardOf(id);
  const st = STATUS[g[4]];
  const p1 = g[0], p2 = g[1], turn = g[2], winner = g[3], lastMove = Number(g[5]);

  let head = `<b>Game #${id}</b> — <span class="pill ${st === "Active" ? "on" : ""}">${st}</span><br>`;
  head += `<span style="color:var(--a)">●</span> ${short(p1)} vs <span style="color:var(--b)">●</span> ${p2 === ethers.ZeroAddress ? '<span class="muted">waiting…</span>' : short(p2)}<br>`;
  if (st === "Active") {
    const mine = me && turn.toLowerCase() === me.toLowerCase();
    head += mine ? `<b style="color:var(--green)">Your move.</b> ` : `Waiting for ${short(turn)}. `;
    const left = lastMove + TIMEOUT - Math.floor(Date.now() / 1000);
    if (left < 0 && me && turn.toLowerCase() !== me.toLowerCase()) {
      head += `<span class="warn">Opponent timed out — you can claim the win.</span>`;
    } else {
      head += `<span class="muted">timeout in ${Math.max(0, Math.floor(left / 3600))}h</span>`;
    }
  } else if (st === "Finished") {
    head += winner === ethers.ZeroAddress ? "<b>Draw.</b>" : `<b>Winner: ${short(winner)}</b>${me && winner.toLowerCase() === me.toLowerCase() ? " 🏆" : ""}`;
  }
  $("gameHead").innerHTML = head;

  // board render (row 5 top … row 0 bottom)
  const bd = $("board");
  bd.innerHTML = "";
  for (let r = 5; r >= 0; r--) {
    for (let c = 0; c < 7; c++) {
      const v = Number(board[r * 7 + c]);
      const cell = document.createElement("div");
      cell.className = "cell" + (v === 1 ? " p1" : v === 2 ? " p2" : "");
      bd.appendChild(cell);
    }
  }
  // column buttons
  const cs = $("colsel");
  cs.innerHTML = "";
  const myTurn = st === "Active" && me && turn.toLowerCase() === me.toLowerCase();
  for (let c = 0; c < 7; c++) {
    const b = document.createElement("button");
    b.textContent = "▼";
    b.disabled = !myTurn || Number(board[5 * 7 + c]) !== 0;
    b.onclick = () => playMove(id, c);
    cs.appendChild(b);
  }
  // actions
  const act = $("actions");
  act.innerHTML = "";
  if (st === "Open" && me && p1.toLowerCase() === me.toLowerCase()) {
    const cb = document.createElement("button");
    cb.className = "ghost"; cb.textContent = "Cancel game";
    cb.onclick = async () => { await send("cancelGame", [id]); };
    act.appendChild(cb);
  }
  if (st === "Active" && me && turn.toLowerCase() !== me.toLowerCase()) {
    const left = lastMove + TIMEOUT - Math.floor(Date.now() / 1000);
    if (left < 0) {
      const tb = document.createElement("button");
      tb.textContent = "Claim timeout win";
      tb.onclick = async () => { await send("claimTimeout", [id]); };
      act.appendChild(tb);
    }
  }
}

async function send(method, args) {
  try {
    const tx = await contract[method](...args);
    log(`${method} tx sent: ${tx.hash}`);
    await tx.wait();
    log(`${method} confirmed.`);
    await refreshLists();
    if (currentGame !== null) renderGame(currentGame);
  } catch (e) {
    log(`${method} failed: ` + (e.shortMessage || e.reason || e.message));
  }
}

async function playMove(id, col) { await send("play", [id, col]); }
async function joinGame(id) {
  if (!me) { log("Connect your wallet first."); return; }
  await send("joinGame", [id]);
  renderGame(Number(id));
}

$("connectBtn").onclick = connect;
$("newGameBtn").onclick = async () => {
  await send("createGame", []);
  const n = await contract.gamesCount();
  renderGame(Number(n) - 1);
};
$("refreshBtn").onclick = () => { refreshLists(); if (currentGame !== null) renderGame(currentGame); };

init();
