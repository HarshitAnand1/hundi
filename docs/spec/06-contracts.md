> Extracted from docs/HANDOFF.md Section 6. Edit the handoff, not this file, or record changes in docs/DECISIONS.md.

## 6. Smart contract specification

### 6.1 The Terms struct (immutable, hashed into the vault address)
 seller, buyer, token (USDC.e), faceAmount, dueDate, invoiceHash, advanceBps,
feeAnnualBps, lateAnnualBps, bondBps, protocolFeeBps, graceSeconds,
defaultSeconds, pool, protocolTreasury

 termsHash = keccak256(abi.encode(terms)) . The vault is a deterministic clone: salt =
termsHash , address from Clones.predictDeterministicAddress . Because the address
commits to every term, no one can later change the waterfall without changing the
address the buyer signed.

### 6.2 Contracts and functions
AcceptanceRegistry

      accept(Acceptance a, bytes sig) : verifies EIP-712 signature (ECDSA, or ERC-1271
     for contract wallets via OpenZeppelin SignatureChecker ), expiry, unused nonce,
     unused invoiceKey = keccak256(seller, buyer, invoiceNumberHash) .
      isAccepted(termsHash) , acceptanceOf(termsHash) .
      Acceptance : buyer, seller, token, faceAmount, dueDate, invoiceHash,
     termsHash, vault, nonce, expiry .

ReceivableFactory

      predictVault(Terms) (pure view), createVault(Terms) (requires acceptance;
     permissionless; atomic initialize).

ReceivableVault

      fund(address lender, uint256 advance) : pool only, once. Pays seller advance −
     bond .

      settle() : permissionless; reads token balance; applies waterfall; idempotent and
     monotonic.
      declareDefault() : permissionless after dueDate + defaultSeconds if unsettled.

      claim(address) : pull fallback. cancel() : if Open and acceptance expired.
      amountDue() view: lender due including late interest at the current time.

LiquidityPool (ERC-4626)

     Standard deposit / withdraw / redeem . Withdrawals limited to idle liquidity.
      advance(Terms, Acceptance, sig) : checks registry, advanceBps <=
     maxAdvanceBps , feeAnnualBps >= minFeeBps , tenor <= maxTenorDays , per-buyer
     and per-seller exposure caps, not paused.
      guardian can pause new advances only. Never funds withdrawal.

ReceivableNote (L2)

     ERC-721 minted at funding to the lender. The vault pays ownerOf(tokenId) . Transfer is
     the secondary market.

### 6.3 Events
 InvoiceAccepted , VaultCreated , Advanced , Settled(lenderPaid, protocolPaid,
sellerPaid, daysLate) , DefaultDeclared , BondForfeited , Claimed . Every dashboard
element must be reconstructable from events alone.

### 6.4 Invariants (write these as Foundry invariant tests before the code)
 1. Conservation: tokens that enter a vault equal tokens that leave plus tokens waiting in
    claim .
 2. Single financing: a termsHash is funded at most once; an invoiceKey is accepted at
    most once.
 3. Lender first: lender due is always paid before protocol fee and seller residual.

 4. Bounded advance: advance never exceeds advanceBps × face or pool exposure
     caps.
 5. Valid acceptance only: state moves to Accepted only with a valid buyer signature.
 6. Address determinism: the vault address is a pure function of the terms.
 7. Monotonic state: no state moves backwards; settle() cannot double-pay.
 8. No frozen funds: a failing recipient never blocks others.
 9. Reputation integrity: records are written only for funded receivables.

### 6.5 Security notes
     Use nonReentrant , checks-effects-interactions, and SafeERC20 .
     Tokens sent to the vault before it is deployed are fine: the vault reads balanceOf at
     settle time.
     Treat dust and unsolicited transfers as overpayment to the seller.
     Use OpenZeppelin for clones, ERC-4626, ERC-721, ECDSA and SignatureChecker. Do
     not hand-roll cryptography.
     Pin Solidity and OpenZeppelin versions; commit foundry.lock or equivalent.

