;; Guardian Wallet
;; Stage 2: Adding guardian system with multi-signature capabilities
;; This contract implements a wallet with guardians who can collectively help the owner.

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
(define-constant ERR_GUARDIAN_ALREADY_EXISTS (err u103))
(define-constant ERR_GUARDIAN_DOESNT_EXIST (err u104))
(define-constant ERR_OPERATION_IN_PROGRESS (err u105))
(define-constant ERR_NO_OPERATION_IN_PROGRESS (err u106))
(define-constant ERR_GUARDIAN_ALREADY_CONFIRMED (err u107))
(define-constant ERR_INSUFFICIENT_CONFIRMATIONS (err u108))
(define-constant ERR_OPERATION_EXPIRED (err u109))
(define-constant ERR_INSUFFICIENT_FUNDS (err u110))
(define-constant ERR_INVALID_THRESHOLD (err u111))

;; Data variables

;; Owner of the wallet
(define-data-var owner principal tx-sender)

;; Whether the wallet has been initialized
(define-data-var initialized bool false)

;; List of guardians
(define-map guardians principal bool)

;; Total number of guardians
(define-data-var guardian-count uint u0)

;; Threshold required for actions (percentage 1-100)
(define-data-var action-threshold uint u51)

;; Operation state
(define-data-var operation-in-progress bool false)
(define-data-var operation-type (optional (string-ascii 20)) none)
(define-data-var operation-proposed-by (optional principal) none)
(define-data-var operation-payload (optional (buff 34)) none)
(define-data-var operation-proposal-expiry uint u0)
(define-map operation-confirmations principal bool)
(define-data-var operation-confirmation-count uint u0)

;; Constants
(define-constant SECONDS_IN_DAY u86400)
(define-constant OPERATION_EXPIRY_DAYS u3)

;; Read-only functions

;; Check if caller is the owner
(define-read-only (is-owner)
  (is-eq tx-sender (var-get owner)))

;; Check if caller is a guardian
(define-read-only (is-guardian (guardian principal))
  (default-to false (map-get? guardians guardian)))

;; Get action threshold
(define-read-only (get-action-threshold)
  (var-get action-threshold))

;; Check if an operation is in progress
(define-read-only (operation-status)
  {
    in-progress: (var-get operation-in-progress),
    operation-type: (var-get operation-type),
    proposed-by: (var-get operation-proposed-by),
    payload: (var-get operation-payload),
    expiry: (var-get operation-proposal-expiry),
    confirmations: (var-get operation-confirmation-count),
    required-confirmations: (calculate-required-confirmations)
  })

;; Calculate required number of confirmations based on threshold
(define-read-only (calculate-required-confirmations)
  (let 
    (
      (guardian-total (var-get guardian-count))
      (threshold (var-get action-threshold))
    )
    (if (is-eq guardian-total u0)
      u0
      (let
        (
          (required-raw (/ (* guardian-total threshold) u100))
          ;; Round up if there's a remainder
          (has-remainder (> (* required-raw u100) (* guardian-total threshold)))
        )
        (if has-remainder
          (+ required-raw u1)
          required-raw
        )
      )
    )
  ))

;; Get the total number of guardians
(define-read-only (get-guardian-count)
  (ok (var-get guardian-count)))

;; Check if a guardian has confirmed an operation
(define-read-only (has-confirmed-operation (guardian principal))
  (default-to false (map-get? operation-confirmations guardian)))

;; Public functions

;; Initialize the wallet
(define-public (initialize (new-owner principal) (initial-threshold uint))
  (begin
    ;; Check if already initialized
    (asserts! (not (var-get initialized)) ERR_ALREADY_INITIALIZED)
    
    ;; Validate threshold
    (asserts! (and (>= initial-threshold u1) (<= initial-threshold u100)) ERR_INVALID_THRESHOLD)
    
    ;; Set owner and mark as initialized
    (var-set owner new-owner)
    (var-set action-threshold initial-threshold)
    (var-set initialized true)
    
    (ok true)))

;; Add a guardian - only owner can add guardians
(define-public (add-guardian (guardian principal))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can add guardians
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Check if guardian already exists
    (asserts! (not (is-guardian guardian)) ERR_GUARDIAN_ALREADY_EXISTS)
    
    ;; Add guardian and increment count
    (map-set guardians guardian true)
    (var-set guardian-count (+ (var-get guardian-count) u1))
    
    (ok true)))

;; Remove a guardian - only owner can remove guardians
(define-public (remove-guardian (guardian principal))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can remove guardians
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Check that no operation is in progress
    (asserts! (not (var-get operation-in-progress)) ERR_OPERATION_IN_PROGRESS)
    
    ;; Check if guardian exists
    (asserts! (is-guardian guardian) ERR_GUARDIAN_DOESNT_EXIST)
    
    ;; Remove guardian and decrement count
    (map-delete guardians guardian)
    (var-set guardian-count (- (var-get guardian-count) u1))
    
    (ok true)))

;; Change action threshold - only owner can change
(define-public (set-action-threshold (new-threshold uint))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can change threshold
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Validate threshold
    (asserts! (and (>= new-threshold u1) (<= new-threshold u100)) ERR_INVALID_THRESHOLD)
    
    ;; Set new threshold
    (var-set action-threshold new-threshold)
    
    (ok true)))

;; Propose a new operation - only guardians can propose
(define-public (propose-operation (operation-id (string-ascii 20)) (payload (buff 34)))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only guardians can propose operations
    (asserts! (is-guardian tx-sender) ERR_UNAUTHORIZED)
    
    ;; Check that no operation is in progress
    (asserts! (not (var-get operation-in-progress)) ERR_OPERATION_IN_PROGRESS)
    
    ;; Set operation state
    (var-set operation-in-progress true)
    (var-set operation-type (some operation-id))
    (var-set operation-proposed-by (some tx-sender))
    (var-set operation-payload (some payload))
    (var-set operation-proposal-expiry (+ block-height (* OPERATION_EXPIRY_DAYS SECONDS_IN_DAY)))
    
    ;; Clear previous confirmations
    (var-set operation-confirmation-count u0)
    
    ;; Add first confirmation
    (map-set operation-confirmations tx-sender true)
    (var-set operation-confirmation-count (+ (var-get operation-confirmation-count) u1))
    
    (ok true)))

;; Confirm an operation - only guardians can confirm
(define-public (confirm-operation)
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only guardians can confirm operations
    (asserts! (is-guardian tx-sender) ERR_UNAUTHORIZED)
    
    ;; Check that an operation is in progress
    (asserts! (var-get operation-in-progress) ERR_NO_OPERATION_IN_PROGRESS)
    
    ;; Check if guardian already confirmed
    (asserts! (not (has-confirmed-operation tx-sender)) ERR_GUARDIAN_ALREADY_CONFIRMED)
    
    ;; Check if operation period is still valid
    (asserts! (<= block-height (var-get operation-proposal-expiry)) ERR_OPERATION_EXPIRED)
    
    ;; Add confirmation
    (map-set operation-confirmations tx-sender true)
    (var-set operation-confirmation-count (+ (var-get operation-confirmation-count) u1))
    
    (ok true)))

;; Execute the operation if threshold is met
(define-public (execute-operation)
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Check that an operation is in progress
    (asserts! (var-get operation-in-progress) ERR_NO_OPERATION_IN_PROGRESS)
    
    ;; Check if operation period is still valid
    (asserts! (<= block-height (var-get operation-proposal-expiry)) ERR_OPERATION_EXPIRED)
    
    ;; Check if enough confirmations
    (asserts! (>= (var-get operation-confirmation-count) (calculate-required-confirmations)) ERR_INSUFFICIENT_CONFIRMATIONS)
    
    ;; Reset operation state
    (var-set operation-in-progress false)
    (var-set operation-type none)
    (var-set operation-proposed-by none)
    (var-set operation-payload none)
    (var-set operation-confirmation-count u0)
    
    (ok true)))

;; Cancel an operation - only owner can cancel
(define-public (cancel-operation)
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can cancel operations
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Check that an operation is in progress
    (asserts! (var-get operation-in-progress) ERR_NO_OPERATION_IN_PROGRESS)
    
    ;; Reset operation state
    (var-set operation-in-progress false)
    (var-set operation-type none)
    (var-set operation-proposed-by none)
    (var-set operation-payload none)
    (var-set operation-confirmation-count u0)
    
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