;; Social Recovery Wallet
;; Stage 3: Full implementation with social recovery capabilities
;; This contract implements a wallet with social recovery capabilities.
;; The wallet allows designating "guardians" who can collectively recover access if the owner loses their keys.

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
(define-constant ERR_RECOVERY_IN_PROGRESS (err u105))
(define-constant ERR_RECOVERY_NOT_IN_PROGRESS (err u106))
(define-constant ERR_GUARDIAN_ALREADY_CONFIRMED (err u107))
(define-constant ERR_INSUFFICIENT_CONFIRMATIONS (err u108))
(define-constant ERR_RECOVERY_EXPIRED (err u109))
(define-constant ERR_INSUFFICIENT_FUNDS (err u110))
(define-constant ERR_INVALID_THRESHOLD (err u111))
(define-constant ERR_ZERO_ADDRESS (err u112))
(define-constant ERR_INVALID_AMOUNT (err u113))
(define-constant ERR_INVALID_TOKEN (err u114))

;; Data variables

;; Owner of the wallet
(define-data-var owner principal tx-sender)

;; Whether the wallet has been initialized
(define-data-var initialized bool false)

;; List of guardians
(define-map guardians principal bool)

;; Total number of guardians
(define-data-var guardian-count uint u0)

;; Threshold required for recovery (percentage 1-100)
(define-data-var recovery-threshold uint u51)

;; Recovery state
(define-data-var recovery-in-progress bool false)
(define-data-var recovery-proposed-by (optional principal) none)
(define-data-var recovery-proposed-owner (optional principal) none)
(define-data-var recovery-proposal-expiry uint u0)
(define-map recovery-confirmations principal bool)
(define-data-var recovery-confirmation-count uint u0)

;; Constants
(define-constant SECONDS_IN_DAY u86400)
(define-constant RECOVERY_EXPIRY_DAYS u7)
(define-constant ZERO_ADDRESS 'SP000000000000000000002Q6VF78)

;; Read-only functions

;; Check if caller is the owner
(define-read-only (is-owner)
  (is-eq tx-sender (var-get owner)))

;; Check if caller is a guardian
(define-read-only (is-guardian (guardian principal))
  (default-to false (map-get? guardians guardian)))

;; Get recovery threshold
(define-read-only (get-recovery-threshold)
  (var-get recovery-threshold))

;; Check if recovery is in progress
(define-read-only (recovery-status)
  {
    in-progress: (var-get recovery-in-progress),
    proposed-by: (var-get recovery-proposed-by),
    proposed-owner: (var-get recovery-proposed-owner),
    expiry: (var-get recovery-proposal-expiry),
    confirmations: (var-get recovery-confirmation-count),
    required-confirmations: (calculate-required-confirmations)
  })

;; Calculate required number of confirmations based on threshold
(define-read-only (calculate-required-confirmations)
  (let 
    (
      (guardian-total (var-get guardian-count))
      (threshold (var-get recovery-threshold))
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

;; Get the list of all guardians
(define-read-only (get-guardians)
  (ok (var-get guardian-count)))

;; Check if a guardian has confirmed a recovery
(define-read-only (has-confirmed-recovery (guardian principal))
  (default-to false (map-get? recovery-confirmations guardian)))

;; Public functions

;; Initialize the wallet
(define-public (initialize (new-owner principal) (initial-threshold uint))
  (begin
    ;; Check if already initialized
    (asserts! (not (var-get initialized)) ERR_ALREADY_INITIALIZED)
    
    ;; Validate threshold
    (asserts! (and (>= initial-threshold u1) (<= initial-threshold u100)) ERR_INVALID_THRESHOLD)
    
    ;; Validate owner address
    (asserts! (not (is-eq new-owner ZERO_ADDRESS)) ERR_ZERO_ADDRESS)
    
    ;; Set owner and mark as initialized
    (var-set owner new-owner)
    (var-set recovery-threshold initial-threshold)
    (var-set initialized true)
    
    (ok true)))

;; Add a guardian - only owner can add guardians
(define-public (add-guardian (guardian principal))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can add guardians
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Validate guardian address
    (asserts! (not (is-eq guardian ZERO_ADDRESS)) ERR_ZERO_ADDRESS)
    
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
    
    ;; Check that no recovery is in progress
    (asserts! (not (var-get recovery-in-progress)) ERR_RECOVERY_IN_PROGRESS)
    
    ;; Check if guardian exists
    (asserts! (is-guardian guardian) ERR_GUARDIAN_DOESNT_EXIST)
    
    ;; Remove guardian and decrement count
    (map-delete guardians guardian)
    (var-set guardian-count (- (var-get guardian-count) u1))
    
    (ok true)))

;; Change recovery threshold - only owner can change
(define-public (set-recovery-threshold (new-threshold uint))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can change threshold
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Validate threshold
    (asserts! (and (>= new-threshold u1) (<= new-threshold u100)) ERR_INVALID_THRESHOLD)
    
    ;; Set new threshold
    (var-set recovery-threshold new-threshold)
    
    (ok true)))

;; Initiate recovery process - only guardians can initiate
(define-public (initiate-recovery (new-owner principal))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only guardians can initiate recovery
    (asserts! (is-guardian tx-sender) ERR_UNAUTHORIZED)
    
    ;; Check that no recovery is in progress
    (asserts! (not (var-get recovery-in-progress)) ERR_RECOVERY_IN_PROGRESS)
    
    ;; Validate new owner address
    (asserts! (not (is-eq new-owner ZERO_ADDRESS)) ERR_ZERO_ADDRESS)
    
    ;; Set recovery state
    (var-set recovery-in-progress true)
    (var-set recovery-proposed-by (some tx-sender))
    (var-set recovery-proposed-owner (some new-owner))
    (var-set recovery-proposal-expiry (+ block-height (* RECOVERY_EXPIRY_DAYS SECONDS_IN_DAY)))
    
    ;; Clear previous confirmations
    (var-set recovery-confirmation-count u0)
    
    ;; Add first confirmation
    (map-set recovery-confirmations tx-sender true)
    (var-set recovery-confirmation-count (+ (var-get recovery-confirmation-count) u1))
    
    (ok true)))

;; Confirm recovery - only guardians can confirm
(define-public (confirm-recovery)
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only guardians can confirm recovery
    (asserts! (is-guardian tx-sender) ERR_UNAUTHORIZED)
    
    ;; Check that recovery is in progress
    (asserts! (var-get recovery-in-progress) ERR_RECOVERY_NOT_IN_PROGRESS)
    
    ;; Check if guardian already confirmed
    (asserts! (not (has-confirmed-recovery tx-sender)) ERR_GUARDIAN_ALREADY_CONFIRMED)
    
    ;; Check if recovery period is still valid
    (asserts! (<= block-height (var-get recovery-proposal-expiry)) ERR_RECOVERY_EXPIRED)
    
    ;; Add confirmation
    (map-set recovery-confirmations tx-sender true)
    (var-set recovery-confirmation-count (+ (var-get recovery-confirmation-count) u1))
    
    (ok true)))

;; Execute recovery if threshold is met
(define-public (execute-recovery)
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Check that recovery is in progress
    (asserts! (var-get recovery-in-progress) ERR_RECOVERY_NOT_IN_PROGRESS)
    
    ;; Check if recovery period is still valid
    (asserts! (<= block-height (var-get recovery-proposal-expiry)) ERR_RECOVERY_EXPIRED)
    
    ;; Check if enough confirmations
    (asserts! (>= (var-get recovery-confirmation-count) (calculate-required-confirmations)) ERR_INSUFFICIENT_CONFIRMATIONS)
    
    ;; Get the proposed new owner and validate
    (let ((new-owner (unwrap! (var-get recovery-proposed-owner) ERR_NOT_INITIALIZED)))
      ;; Double-check the new owner is valid (extra safety)
      (asserts! (not (is-eq new-owner ZERO_ADDRESS)) ERR_ZERO_ADDRESS)
      
      ;; Update owner
      (var-set owner new-owner)
      
      ;; Reset recovery state
      (var-set recovery-in-progress false)
      (var-set recovery-proposed-by none)
      (var-set recovery-proposed-owner none)
      (var-set recovery-confirmation-count u0)
    )
    
    (ok true)))

;; Cancel recovery - only owner can cancel
(define-public (cancel-recovery)
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can cancel recovery
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Check that recovery is in progress
    (asserts! (var-get recovery-in-progress) ERR_RECOVERY_NOT_IN_PROGRESS)
    
    ;; Reset recovery state
    (var-set recovery-in-progress false)
    (var-set recovery-proposed-by none)
    (var-set recovery-proposed-owner none)
    (var-set recovery-confirmation-count u0)
    
    (ok true)))

;; Transfer funds to another address - only owner can transfer
(define-public (transfer (token <ft-trait>) (recipient principal) (amount uint))
  (begin
    ;; Check if contract is initialized
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    
    ;; Only owner can transfer
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    
    ;; Validate recipient and amount
    (asserts! (not (is-eq recipient ZERO_ADDRESS)) ERR_ZERO_ADDRESS)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
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
    
    ;; Validate recipient and amount
    (asserts! (not (is-eq recipient ZERO_ADDRESS)) ERR_ZERO_ADDRESS)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Check if enough balance
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer STX
    (stx-transfer? amount tx-sender recipient)
  ))

;; Get current owner
(define-read-only (get-owner)
  (ok (var-get owner)))