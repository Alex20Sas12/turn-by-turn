# Deployed

- **Network:** Base Sepolia (chainId 84532)
- **Contract:** `0x8621067F8de51DEE4E215a6A9F7E668C0333cD7C`
  - https://sepolia.basescan.org/address/0x8621067F8de51DEE4E215a6A9F7E668C0333cD7C
  - Source verified on Sourcify: `exact_match`
- **Deploy tx:** `0x22da151629109e8f8933571b3d0ade7e27bc24d1e35c385c2f61a1f9297bd4cc`
- **Web app:** https://turn-by-turn-pied.vercel.app
- **Repo:** https://github.com/Alex20Sas12/turn-by-turn

## Onchain smoke test (2026-10-09)

- Game #0 created by deployer: tx `0x73b85bca472d1c711d58c60b0ac5d757c566c435695d1164f2b780ee21d68e1b`
- Second wallet joined, both played into column 3 — board state correct, turn flipped back to player 1.
- `play` before second player joins reverts with `GameNotActive` (verified).
