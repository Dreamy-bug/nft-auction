// NFT 拍卖前端演示逻辑 —— ethers v6 + MetaMask
const ZERO = "0x0000000000000000000000000000000000000000";
const CHAIN_ID = 11155111n; // Sepolia 测试网

const App = {
  provider: null, signer: null, account: null,
  auction: null, nft: null, usdc: null, v2: null, ethFeed: null,

  async connect() {
    if (!window.ethers || !window.ethers.JsonRpcProvider) { this.log("ethers 未加载（CDN？）", "err"); return; }
    if (!window.ethereum) { this.log("未检测到 MetaMask，请安装", "err"); return; }
    try {
      await window.ethereum.request({ method: "eth_requestAccounts" });
      this.provider = new ethers.BrowserProvider(window.ethereum);
      this.signer = await this.provider.getSigner();
      this.account = await this.signer.getAddress();
      const net = await this.provider.getNetwork();
      if (net.chainId !== CHAIN_ID) {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: "0x" + CHAIN_ID.toString(16) }],
        }).catch(async () => {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [{ chainId: "0x" + CHAIN_ID.toString(16), chainName: "Sepolia",
              nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
              rpcUrls: ["https://ethereum-sepolia-rpc.publicnode.com"],
              blockExplorerUrls: ["https://sepolia.etherscan.io"] }],
          });
        });
        this.provider = new ethers.BrowserProvider(window.ethereum);
        this.signer = await this.provider.getSigner();
      }
      this.bindContracts();
      this.renderAccounts();
      window.ethereum.on?.("accountsChanged", () => location.reload());
      window.ethereum.on?.("chainChanged", () => location.reload());
      await this.refreshAll();
      this.log("已连接 " + this.account, "ok");
    } catch (e) { this.log("连接失败: " + this.reason(e), "err"); }
  },

  bindContracts() {
    this.auction = new ethers.Contract(CONTRACTS.PROXY, ABIS.NFTAuction, this.signer);
    this.nft = new ethers.Contract(CONTRACTS.NFT, ABIS.MyNFT, this.signer);
    this.usdc = new ethers.Contract(CONTRACTS.USDC, ABIS.MockERC20, this.signer);
    this.v2 = new ethers.Contract(CONTRACTS.PROXY, [...ABIS.NFTAuction, ...ABIS.NFTAuctionV2], this.signer);
    this.ethFeed = new ethers.Contract(CONTRACTS.ETH_USD_FEED, ABIS.MockAggregator, this.provider);
  },

  roleOf(addr) {
    const a = addr.toLowerCase();
    const acc = ACCOUNTS.find(x => x.addr.toLowerCase() === a);
    return acc ? acc.role : "未知";
  },
  keyOf(addr) {
    const a = addr.toLowerCase();
    const acc = ACCOUNTS.find(x => x.addr.toLowerCase() === a);
    return acc ? acc.key : null;
  },

  async refreshAll() {
    await this.updateHeader();
    const dep = document.getElementById("deployInfo");
    const c = CONTRACTS;
    let ethPrice = "？";
    try { const r = await this.ethFeed.latestRoundData(); ethPrice = (Number(r[1]) / 1e8).toFixed(2); } catch {}
    dep.innerHTML =
      `Proxy(拍卖合约): <span class="mono">${c.PROXY}</span><br>` +
      `MyNFT: <span class="mono">${c.NFT}</span><br>` +
      `USDC: <span class="mono">${c.USDC}</span> (18 decimals, $1)<br>` +
      `ETH/USD Feed: <span class="mono">${c.ETH_USD_FEED}</span> (ETH=$${ethPrice})<br>` +
      `V2 实现: <span class="mono">${c.IMPL_V2}</span><br>` +
      `Owner/feeRecipient: <span class="mono">${ACCOUNTS[0].addr}</span>`;
    await this.refreshCounter();
    await this.refreshAuction();
  },

  async updateHeader() {
    document.getElementById("acctInfo").textContent = this.account;
    document.getElementById("netInfo").textContent = "Sepolia 11155111";
    const role = this.roleOf(this.account);
    const rt = document.getElementById("roleTag");
    rt.style.display = "inline-block"; rt.textContent = "角色: " + role;
    const bal = await this.provider.getBalance(this.account);
    document.getElementById("balTag").style.display = "inline-block";
    document.getElementById("balTag").textContent = "余额 " + (+ethers.formatEther(bal)).toFixed(3) + " ETH";
  },

  renderAccounts() {
    const list = ACCOUNTS.map((a, i) =>
      `<div>(${i}) <b>${a.role}</b> <span class="mono">${a.addr}</span> · key <span class="mono">${a.key}</span></div>`
    ).join("");
    document.getElementById("acctList").innerHTML = list;
  },

  copyKey() {
    const k = this.keyOf(this.account);
    if (!k) { this.log("当前账户不在演示账户列表中", "err"); return; }
    navigator.clipboard?.writeText(k);
    this.log("已复制私钥（仅本地演示用）: " + k, "ok");
  },

  // ===== 0. 准备工具 =====
  async mintNFT() {
    const to = document.getElementById("mintTo").value.trim() || this.account;
    try {
      const tx = await this.nft.mint(to, "ipfs://demo/" + Date.now());
      const r = await tx.wait();
      const ev = this.parseEvent(r, this.nft, "Transfer");
      this.log(`铸 NFT 成功 tokenId=${ev?.args?.tokenId ?? "?"} → ${to}`, "ok");
    } catch (e) { this.log("铸NFT失败: " + this.reason(e), "err"); }
  },
  async mintUSDC() {
    const to = document.getElementById("usdcTo").value.trim() || this.account;
    const amt = BigInt(document.getElementById("usdcAmt").value) * 10n ** 18n;
    try { const tx = await this.usdc.mint(to, amt); await tx.wait(); this.log(`铸 ${amt / 10n ** 18n} USDC → ${to}`, "ok"); }
    catch (e) { this.log("铸USDC失败: " + this.reason(e), "err"); }
  },

  // ===== 1. 卖家 =====
  async approveNFT() {
    try { const tx = await this.nft.setApprovalForAll(CONTRACTS.PROXY, true); await tx.wait();
      this.log("setApprovalForAll 完成", "ok"); }
    catch (e) { this.log("授权失败: " + this.reason(e), "err"); }
  },
  async createAuction() {
    const tokenId = document.getElementById("cTokenId").value;
    const startUsd = Math.round(parseFloat(document.getElementById("cStart").value) * 1e8);
    const dur = document.getElementById("cDur").value;
    try {
      const tx = await this.auction.createAuction(CONTRACTS.NFT, tokenId, startUsd, dur);
      const r = await tx.wait();
      const ev = this.parseEvent(r, this.auction, "AuctionCreated");
      const id = ev?.args?.auctionId?.toString();
      document.getElementById("lastId").textContent = id ?? "?";
      document.getElementById("bId").value = id || 1;
      document.getElementById("eId").value = id || 1;
      document.getElementById("wId").value = id || 1;
      this.log(`创建拍卖成功 id=${id} 起拍 $${startUsd / 1e8} 持续 ${dur}s`, "ok");
      await this.refreshCounter(); await this.refreshAuction();
    } catch (e) { this.log("创建拍卖失败: " + this.reason(e), "err"); }
  },
  async refreshCounter() {
    try { const c = await this.auction.auctionCounter(); document.getElementById("counter").textContent = c.toString(); }
    catch {}
  },

  // ===== 2. 竞拍 =====
  async refreshAuction() {
    const id = document.getElementById("bId").value;
    const el = document.getElementById("aucInfo");
    try {
      const a = await this.auction.auctions(id);
      const end = Number(a.endTime);
      const now = Math.floor(Date.now() / 1000);
      const left = end > now ? `${end - now}s 后结束` : `已结束`;
      const token = a.highestBidToken === ZERO ? "ETH" : (a.highestBidToken === CONTRACTS.USDC ? "USDC" : a.highestBidToken);
      el.innerHTML =
        `seller: <span class="mono">${a.seller}</span><br>` +
        `tokenId: ${a.tokenId} · 起拍 $${(+a.startPriceUsd) / 1e8} · 最高 $${(+a.highestBidUsd) / 1e8}<br>` +
        `最高出价者: <span class="mono">${a.highestBidder}</span> (${token} ${a.highestBidAmount.toString()})<br>` +
        `endTime: ${end} (${left}) · active=${a.active} ended=${a.ended}`;
      try { const min = await this.auction.getMinBidUsd(id); this.log(`最低出价 = $${(+min) / 1e8}`, "dim"); } catch {}
    } catch (e) { el.textContent = "查询失败: " + this.reason(e); }
  },
  async bidEth() {
    const id = document.getElementById("bId").value;
    const eth = document.getElementById("bEth").value;
    try {
      const tx = await this.auction.bidWithEth(id, { value: ethers.parseEther(eth) });
      const r = await tx.wait();
      const ev = this.parseEvent(r, this.auction, "BidPlaced");
      this.log(`ETH 出价成功 ${eth} ETH (≈$${(+ev?.args?.amountUsd) / 1e8})`, "ok");
      await this.refreshAuction();
    } catch (e) { this.log("出价失败: " + this.reason(e), "err"); }
  },
  async approveUSDC() {
    try { const tx = await this.usdc.approve(CONTRACTS.PROXY, ethers.MaxUint256); await tx.wait();
      this.log("USDC approve 完成", "ok"); }
    catch (e) { this.log("approve 失败: " + this.reason(e), "err"); }
  },
  async bidERC20() {
    const id = document.getElementById("bId").value;
    const usdc = BigInt(document.getElementById("bUsdc").value) * 10n ** 18n;
    try {
      const tx = await this.auction.bidWithERC20(id, CONTRACTS.USDC, usdc);
      const r = await tx.wait();
      const ev = this.parseEvent(r, this.auction, "BidPlaced");
      this.log(`USDC 出价成功 ${usdc / 10n ** 18n} USDC (≈$${(+ev?.args?.amountUsd) / 1e8})`, "ok");
      await this.refreshAuction();
    } catch (e) { this.log("出价失败: " + this.reason(e), "err"); }
  },

  // ===== 3. 结算 =====
  async endAuction() {
    const id = document.getElementById("eId").value;
    const el = document.getElementById("endInfo");
    try {
      const tx = await this.auction.endAuction(id);
      const r = await tx.wait();
      const ev = this.parseEvent(r, this.auction, "AuctionEnded");
      const winner = ev?.args?.winner ?? ethers.ZeroAddress;
      const token = ev?.args?.paymentToken;
      const amt = ev?.args?.amount?.toString();
      el.innerHTML = winner === ethers.ZeroAddress
        ? "拍卖流拍（无出价）"
        : `中标者: <span class="mono">${winner}</span><br>支付: ${token === ZERO ? amt / 1e18 + " ETH" : (token === CONTRACTS.USDC ? amt / 1e18 + " USDC" : "?")} · NFT 已转给中标者 · 手续费已分给 feeRecipient`;
      this.log("结算完成", "ok");
      await this.refreshAuction();
    } catch (e) { el.textContent = "结算失败: " + this.reason(e); this.log("结算失败: " + this.reason(e), "err"); }
  },

  // ===== 4. 退款 =====
  async checkPending() {
    const id = document.getElementById("wId").value;
    const el = document.getElementById("pendingInfo");
    try {
      const eth = await this.auction.pendingReturns(id, this.account, ZERO);
      const usdc = await this.auction.pendingReturns(id, this.account, CONTRACTS.USDC);
      el.innerHTML = `待退 ETH: ${ethers.formatEther(eth)} · 待退 USDC: ${ethers.formatEther(usdc)}`;
    } catch (e) { el.textContent = "查询失败: " + this.reason(e); }
  },
  async withdraw(token) {
    const id = document.getElementById("wId").value;
    try { const tx = await this.auction.withdrawPendingReturn(id, token); await tx.wait();
      this.log("提取 ETH 退款完成", "ok"); await this.checkPending(); }
    catch (e) { this.log("提取失败: " + this.reason(e), "err"); }
  },
  async withdrawUsdc() {
    const id = document.getElementById("wId").value;
    try { const tx = await this.auction.withdrawPendingReturn(id, CONTRACTS.USDC); await tx.wait();
      this.log("提取 USDC 退款完成", "ok"); await this.checkPending(); }
    catch (e) { this.log("提取失败: " + this.reason(e), "err"); }
  },

  // ===== 5. V2 升级 =====
  async checkVersion() {
    const el = document.getElementById("verInfo");
    try {
      const v = await this.v2.version();
      const dyn = await this.v2.dynamicFeeEnabled();
      el.textContent = `版本 ${v} · 动态手续费=${dyn}`;
      this.log(`版本 ${v} 动态费率 ${dyn}`, "ok");
    } catch { el.textContent = "V1（version() 不存在）"; this.log("当前 V1", "dim"); }
  },
  async upgradeV2() {
    try {
      const initData = this.v2.interface.encodeFunctionData("initializeV2",
        [[250n, 200n, 150n], [1000n * 10n ** 8n, 10000n * 10n ** 8n]]);
      const tx = await this.v2.upgradeToAndCall(CONTRACTS.IMPL_V2, initData);
      await tx.wait();
      this.log("升级到 V2 完成", "ok");
      await this.checkVersion();
    } catch (e) { this.log("升级失败: " + this.reason(e), "err"); }
  },
  async showFeeTiers() {
    const el = document.getElementById("feeInfo");
    try {
      const enabled = await this.v2.dynamicFeeEnabled();
      const t = [await this.v2.feeTiers(0), await this.v2.feeTiers(1), await this.v2.feeTiers(2)];
      const th = [await this.v2.feeThresholds(0), await this.v2.feeThresholds(1)];
      const samples = [500e8, 5000e8, 50000e8].map(async v => (await this.v2.getDynamicFeeBps(BigInt(v))).toString());
      const fees = await Promise.all(samples);
      el.innerHTML = `enabled=${enabled} tiers=[${t.map(x => (+x) / 100 + "%").join("/")}] ` +
        `thr=[$${(+th[0]) / 1e8}/$${(+th[1]) / 1e8}]<br>` +
        `getDynamicFeeBps: $500→${fees[0] / 100}% · $5000→${fees[1] / 100}% · $50000→${fees[2] / 100}%`;
      this.log("费率档查询完成", "ok");
    } catch (e) { el.textContent = "查询失败: " + this.reason(e); this.log("查询失败: " + this.reason(e), "err"); }
  },

  // ===== 工具 =====
  parseEvent(receipt, contract, name) {
    for (const lg of receipt.logs) {
      try { const p = contract.interface.parseLog(lg); if (p && p.name === name) return p; } catch {}
    }
    return null;
  },
  reason(e) {
    if (!e) return "unknown";
    if (e.reason) return e.reason;
    if (e.info?.error?.reason) return e.info.error.reason;
    if (e.shortMessage) return e.shortMessage;
    return e.message || String(e);
  },
  log(msg, cls = "") {
    const el = document.getElementById("log");
    const time = new Date().toLocaleTimeString();
    const div = document.createElement("div");
    if (cls) div.className = cls;
    div.textContent = `[${time}] ${msg}`;
    el.appendChild(div); el.scrollTop = el.scrollHeight;
  },
};

window.App = App;
