;; Wallet Contract: implementation with basic functionality

;; Define fungible token trait
(define-trait ft-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    ;; Get the token balance of the specified principal
    (get-balance (principal) (response uint uint))
  )
)

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_INITIALIZED (err u101))
(define-constant ERR_NOT_INITIALIZED (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u110))

;; Data variables

;; Owner of the wallet
(define-data-var owner principal tx-sender)

;; Whether the wallet has been initialized
(define-data-var initialized bool false)

;; Read-only functions

;; Check if caller is the owner
(define-read-only (is-owner)
  (is-eq tx-sender (var-get owner)))

;; Public functions

;; Initialize the wallet
(define-public (initialize (new-owner principal))
  (begin
    ;; Check if already initialized
    (asserts! (not (var-get initialized)) ERR_ALREADY_INITIALIZED)
    
    ;; Set owner and mark as initialized
    (var-set owner new-owner)
    (var-set initialized true)
    
    (ok true)))

;; Transfer funds to another address - only owner can transfer
(define-public (transfer (token <ft-trait>) (recipient principal) (amount uint))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can transfer
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Transfer tokens
    (contract-call? token transfer amount tx-sender recipient none)
  ))

;; Transfer STX to another address - only owner can transfer
(define-public (transfer-stx (recipient principal) (amount uint))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can transfer
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Check if enough balance
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer STX
    (stx-transfer? amount tx-sender recipient)
  ))

;; Get current owner
(define-read-only (get-owner)
  (ok (var-get owner)))