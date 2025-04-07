
# SocialRecoveryWallet

A Clarity smart contract for building **secure, non-custodial crypto wallets** with **social recovery** features. This wallet allows the owner to appoint trusted "guardians" who can collectively help recover access if the owner loses their keys.

---

## 🚀 Features

- ✅ **Ownership control**: Only the designated owner can manage sensitive actions like transfers.
- 🧑‍🤝‍🧑 **Guardian-based recovery**: Guardians can initiate and confirm ownership recovery.
- ⏱️ **Time-bound recovery proposals**: Recovery proposals expire after a defined time.
- 🔐 **Customizable recovery threshold**: Owner sets what % of guardians are required for recovery.
- 🔁 **STX and token transfers**: Secure transfer of both STX and SIP-010 (fungible) tokens.
- 🛑 **Recovery cancellation**: Owner can cancel a recovery process anytime before it's executed.

---

## 🛠️ Getting Started

### Prerequisites

- **Clarity language knowledge**
- **Stacks blockchain environment**
- **Clarity CLI** or **Stacks JS toolkits** for deployment and interaction

---

## 📄 Contract Overview

### Initialization

```clojure
(initialize (new-owner principal) (initial-threshold uint))
```

Sets up the contract with an initial owner and a recovery threshold (1–100%).

---

### Guardian Management

```clojure
(add-guardian (guardian principal)) ;; Only callable by owner
(remove-guardian (guardian principal)) ;; Only callable by owner
```

Manages the list of trusted accounts that can help with recovery.

---

### Recovery Lifecycle

```clojure
(initiate-recovery (new-owner principal)) ;; Callable by any guardian
(confirm-recovery) ;; Callable by any other guardian
(execute-recovery) ;; Once enough confirmations
(cancel-recovery) ;; Only callable by owner
```

Guardians can propose a new owner and confirm it. The process is complete once the required threshold is met.

Recovery is time-limited (7 days by default).

---

### Fund Transfers

#### STX Transfers
```clojure
(transfer-stx (recipient principal) (amount uint)) ;; Only by owner
```

#### SIP-010 Token Transfers
```clojure
(transfer (token <ft-trait>) (recipient principal) (amount uint)) ;; Only by owner
```

Safely send funds held by the wallet contract.

---

## 🔐 Security Features

- **Immutable guardianship validation**
- **Zero-address protection**
- **Multiple assertions for all input validations**
- **Recovery confirmations require majority consensus**

---

## 📊 Recovery Threshold Calculation

The required number of confirmations is calculated as:

```clojure
ceil((guardian-count * threshold) / 100)
```

Ensures fractional thresholds are properly rounded up.

---

## 🧪 Read-only Functions

- `(is-owner)`: Check if caller is current owner.
- `(is-guardian principal)`: Check if address is a guardian.
- `(get-owner)`: Get the current wallet owner.
- `(get-guardians)`: Get number of guardians.
- `(has-confirmed-recovery principal)`: Check if guardian has confirmed.
- `(recovery-status)`: View recovery proposal status.
- `(get-recovery-threshold)`: Current threshold set by owner.

---

## 🔧 Future Improvements

- ⛓ Multi-sig transaction support
- 🔁 Recovery cooldown period
- 🔐 Encrypted guardian communication
- 📱 Integration with Stacks wallets

