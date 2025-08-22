import { HDNodeWallet } from "ethers";
import fs from "fs";

const seed = "ENTER SEED PHRASE";

const root = HDNodeWallet.fromPhrase(seed, undefined, "m");

const wallets = [];
for (let i = 0; i < 150; i++) {
  const child = root.derivePath(`m/44'/60'/0'/0/${i}`);
  wallets.push({ index: i, address: child.address, privateKey: child.privateKey });
}

fs.writeFileSync("wallets1.json", JSON.stringify(wallets, null, 2));
console.log("Wrote 100 wallets to wallets.json");
