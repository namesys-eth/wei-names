## Wei Names (WNS)

> **⚠ Reverse**: WNS does **NOT** use ENS's `ReverseRegistrar` / `addr.reverse`. NameNFT and ProquintNFT each have their own `primaryName` on-chain. WNS provides a simple bidirectional reverse as fallback only.

### Contracts

```
WNS.sol       = Registry + Resolver + Bridge  (single L1 contract)
NameNFT.sol   = .wei ERC721 registrar         (standalone, deployed)
ProquintNFT   = proquint ERC721 registrar     (lib/proquint.eth)
OPBridge.sol  = Superchain bridge helper      (standalone, bridge/Base.sol)
```

---

### How ENS Resolution Works (Reference)

ENS uses a two-step process:

1. **Registry** (`ENSRegistry`) — stores `owner`, `resolver`, `ttl` per node. Client calls `registry.resolver(node)` to get the resolver address.
2. **Resolver** (`PublicResolver`) — separate contract that stores records (`addr`, `text`, `contenthash`, etc). Client calls `resolver.addr(node)` etc.
3. **UniversalResolver** — off-chain helper that walks DNS-encoded names through the registry via `findResolver(name)`, then calls `resolve(name, data)` (ENSIP-10/EIP-3668) on the found resolver.
4. **ReverseRegistrar** — standalone contract that owns `addr.reverse` in the ENS registry. Creates `<hex>.addr.reverse` subnodes and sets `name()` records.

### How WNS Maps to ENS

WNS combines registry + resolver + bridge into **one contract**. It implements the same ENS interfaces so existing clients/libraries work:

| ENS | WNS equivalent |
|-----|---------------|
| `ENSRegistry.resolver(node)` | `Registry.resolver(node)` — checks WNS → ENS → PRO |
| `ENSRegistry.owner(node)` | `Registry.owner(node)` — checks WNS → ENS → PRO |
| `UniversalResolver.findResolver(name)` | `Registry.resolver(bytes name)` — DNS decode + TLD classify |
| `PublicResolver.resolve(name, data)` | `Resolver.resolve(name, data)` — same contract |
| `ReverseRegistrar` | **Not used.** NameNFT/ProquintNFT have `primaryName`. Simple `Reverse.sol` as fallback. |

---

### Registry (`Registry.sol`)

#### `resolver(bytes32 node)`

Standard ENS-compatible lookup:
1. `WNS.ownerOf(node)` → if owned → `address(this)`
2. `ENS.resolver(node)` → if set → return it (ENS resolver)
3. `PRO.recordExists(node)` → if exists → `address(this)`

#### `resolver(bytes name)` — DNS-encoded name

This is WNS's equivalent of ENS `UniversalResolver.findResolver()`. Decodes DNS wire format, classifies TLD, walks to find the deepest resolver:

- **`.wei`** — verify `WNS.ownerOf(domain.wei)`, walk subdomain `_nodes[].resolver`, fallback `address(this)`
- **`.eth` / ICANN** — walk `ENS.resolver(node)` from TLD inward (standard ENS behavior)
- **Proquint** (11-byte label) — `PRO.recordExists(node)`, walk subdomains, fallback `address(this)`
- **Address** (42-byte `0x...`) — validate hex, walk subdomains, fallback `address(this)`
- **Reverse** (`addr.reverse`) — check local `_nodes` resolver → `ENS.resolver` → fallback `address(this)`

#### `owner(node)`, `recordExists(node)`, `ttl(node)`

All ENS-compatible. `owner` and `recordExists` check across WNS → ENS → PRO. `ttl` returns 0.

---

### Resolver (`Resolver.sol`)

When `resolver(name)` returns `address(this)`, the client calls `resolve(name, request)` on the same contract. This is the ENSIP-10 wildcard resolve entrypoint.

#### `resolve(name, request)` — order of operations

```
1. Direct record at node
   → _recordAt(node, hash(request)), return if found

2. Redirect at node
   → _resolveRedirect(node, key), follow to target, return if found

3. DNS decode
   → parse name into labelhashes, build domain string and path

4. TLD classify + walk
   → .wei:      advance to domain.wei, try NameNFT fallback (addr/contenthash/text)
   → proquint:  check PRO.recordExists
   → address:   validate 0x... hex
   → reverse:   walk addr.reverse
   → .eth:      ENS fallthrough
   → walk remaining subdomains, track activeNode (deepest with resolver == this)

5. ActiveNode lookup
   → try direct record at activeNode
   → try redirect at activeNode

6. CCIP-Read fallback
   → check recordhash at node, then activeNode
   → if found: revert OffchainLookup (EIP-3668)

7. Return empty
```

---

### Resolver Modules

#### Read (`Read.sol`)
Direct record access. `read(node, key)` returns latest. `readBatch` for multiple keys. No redirect following — that's `resolve()`'s job.

#### Write (`Write.sol`)
`write(node, key, data)` with generic auth. `writeENS` / `writeWNS` for namespace-specific auth. Batch variants. Each write increments version.

#### Address (`Address.sol`)
Records keyed by `address` instead of `node`. `write(addr, key, data)` — auth: the address itself, its ERC-173 `owner()`, or approved operator.

#### Proquint (`Proquint.sol`)
Records keyed by `bytes4` proquint ID. Auth via PRO registry owner.

#### Redirect (`Redirect.sol`)
- `setRedirect(node, key, target)` — key-specific
- `setWildcardRedirect(node, target)` — all unset keys
- `enableRedirect(dest, source, key, expiry)` — destination must allow source
- Cascade: `source+key` → `source+WILDCARD` → `WILDCARD+key` → `WILDCARD+WILDCARD`
- Redirects re-key the request with the target node

#### Reverse (`Reverse.sol`)
Simple bidirectional `addressNode ↔ nameNode`. Not ENS `addr.reverse`.

- `setReverse(addr, node)` / `setReverseWNS` / `setReverse(bytes4 id)` / `claimReverse(target)`
- `getReverse(addr)` — checks: explicit reverse → `WNS.primaryName` → `PRO.primaryName`
- `name(node)` — ENS-compatible `name()` record reader

#### Offchain (`Offchain.sol`)
EIP-3668 CCIP-Read with EIP-712 signatures.

- **Recordhash** per node (IPFS/IPNS content pointer)
- **Gateways** managed by owner; URLs built via `Utils.sol`
- **`__callback`** verifies checkhash + recovers EIP-712 signers:
  - `RECORD_TYPEHASH` — signer is owner or on-chain-approved
  - `APPROVAL_TYPEHASH` — two-hop: approver (owner) delegates to signer

---

### Auth (`Auth.sol`)

Ownership priority: **WNS → ENS → PRO** (first match wins).

For each namespace: checks `sender == owner`, then `_approval[owner][node][sender]`, then `_approval[owner][addrNode(owner)][sender]`, then registry `isApprovedForAll`.

Typed variants: `_isAuthorizedENS`, `_isAuthorizedWNS`, `_isAuthorizedPRO`, `_isAuthorizedAddr`.

Address-node auth: `approveAddr(addr, operator)` grants operator access to all of that address's nodes.

---

### Record Storage (`Config.sol`)

```
Node {
  resolver                          — custom resolver (0 = this contract)
  entries[key] → { Record, Pointer }
  redirectAllowlist[src][key]       — expiry timestamp
  reverse[0]                        — paired node
}
Record { val[version] → bytes, latest }
```

- **key** = `keccak256(request)` (full ABI-encoded call)
- Append-only versioned storage. Data may be LibZip compressed.

---

### Bridge

**`registry/Bridge.sol`** (in WNS core): `bridgeENS` / `bridgeWNS` / `bridgeProquint` — auth check then forward to per-chain bridge via `IL1Bridge.claimOnL2(node, chainId)`. Owner sets bridges via `setChainBridge(chainId, addr)`.

**`bridge/OPBridge.sol`** (standalone): single contract for all Superchain L2s. `addChain(chainId, messenger, l2Target, gasLimit)`. Sends cross-domain message via OP Stack `L1CrossDomainMessenger`.

---

### Inheritance

```
Config → Auth → ReadResolver → WriteResolver (+AddressResolver) → ReverseResolver
                Auth → RedirectResolver
                Auth → ProquintResolver
                Auth → OffchainResolver

Registry  (Config + IRegistry)
Resolver  (Auth + Redirect + Reverse + Proquint + Offchain + IResolver)
Bridge    (Auth)
WNS       (Registry + Resolver + Bridge)
```
