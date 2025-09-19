;; cache-manager
;; A Clarity smart contract for managing Arbitrum layer cache operations
;; and tracking cache metadata and performance.
;;
;; This contract enables:
;; - Tracking and managing cache entries
;; - Recording cache performance metrics
;; - Managing cache authorization and validation
;; - Supporting cross-layer caching strategies

;; Error constants
(define-constant ERR-CACHE-NOT-FOUND (err u100))
(define-constant ERR-CACHE-EXISTS (err u101))
(define-constant ERR-UNAUTHORIZED (err u102))
(define-constant ERR-INVALID-CACHE-DATA (err u103))
(define-constant ERR-CACHE-EXPIRED (err u104))
(define-constant ERR-INVALID-PERMISSION (err u105))
(define-constant ERR-MAX-CACHE-SIZE (err u106))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-CACHE-ENTRIES u1000)
(define-constant DEFAULT-TTL u300)  ;; 5 minutes
(define-constant MAX-CACHE-TTL u3600)  ;; 1 hour

;; Cache performance tiers
(define-constant TIER-1-THRESHOLD u25)   ;; Low performance
(define-constant TIER-2-THRESHOLD u50)   ;; Moderate performance
(define-constant TIER-3-THRESHOLD u75)   ;; High performance
(define-constant TIER-4-THRESHOLD u90)   ;; Excellent performance

;; Data structures
(define-map cache-entries
  { key: (string-utf8 64) }
  {
    data: (buff 256),
    created-at: uint,
    ttl: uint,
    is-public: bool,
    hits: uint,
    misses: uint,
    last-accessed: uint
  }
)

;; Track authorized cache managers
(define-map cache-managers
  { manager: principal }
  { active: bool }
)

;; Data variables
(define-data-var total-cache-entries uint u0)
(define-data-var total-cache-hits uint u0)
(define-data-var total-cache-misses uint u0)

;; Private functions

;; Calculate the cache performance tier
(define-private (calculate-performance-tier (hit-rate uint))
  (if (>= hit-rate TIER-4-THRESHOLD)
    u4
    (if (>= hit-rate TIER-3-THRESHOLD)
      u3
      (if (>= hit-rate TIER-2-THRESHOLD)
        u2
        u1
      )
    )
  )
)

;; Check if a principal is an authorized cache manager
(define-private (is-authorized-manager (manager principal))
  (default-to false (get active (map-get? cache-managers { manager: manager })))
)

;; Validate cache entry parameters
(define-private (validate-cache-params (key (string-utf8 64)) (data (buff 256)) (ttl uint))
  (begin
    (asserts! (> (len key) u0) ERR-INVALID-CACHE-DATA)
    (asserts! (<= (len data) u256) ERR-INVALID-CACHE-DATA)
    (asserts! (<= ttl MAX-CACHE-TTL) ERR-INVALID-CACHE-DATA)
    true
  )
)

;; Public functions

;; Create a new cache entry
(define-public (create-cache-entry (key (string-utf8 64)) (data (buff 256)) (ttl uint) (is-public bool))
  (let (
    (current-block-height block-height)
  )
    ;; Validate total cache entries and parameters
    (asserts! (< (var-get total-cache-entries) MAX-CACHE-ENTRIES) ERR-MAX-CACHE-SIZE)
    (validate-cache-params key data ttl)
    
    ;; Check if cache entry already exists
    (asserts! (is-none (map-get? cache-entries { key: key })) ERR-CACHE-EXISTS)
    
    ;; Create new cache entry
    (map-set cache-entries
      { key: key }
      {
        data: data,
        created-at: current-block-height,
        ttl: (default-to DEFAULT-TTL ttl),
        is-public: is-public,
        hits: u0,
        misses: u0,
        last-accessed: current-block-height
      }
    )
    
    ;; Increment total cache entries
    (var-set total-cache-entries (+ (var-get total-cache-entries) u1))
    
    (ok true)
  )
)

;; Update existing cache entry
(define-public (update-cache-entry (key (string-utf8 64)) (data (buff 256)) (ttl uint))
  (let (
    (current-block-height block-height)
    (existing-entry (unwrap! (map-get? cache-entries { key: key }) ERR-CACHE-NOT-FOUND))
  )
    ;; Validate parameters
    (validate-cache-params key data ttl)
    
    ;; Update cache entry
    (map-set cache-entries
      { key: key }
      (merge existing-entry {
        data: data,
        ttl: (default-to DEFAULT-TTL ttl),
        last-accessed: current-block-height
      })
    )
    
    (ok true)
  )
)

;; Add a cache manager
(define-public (add-cache-manager (manager principal))
  (begin
    ;; Only contract owner can add managers
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Add the cache manager
    (map-set cache-managers
      { manager: manager }
      { active: true }
    )
    
    (ok true)
  )
)

;; Remove a cache manager
(define-public (remove-cache-manager (manager principal))
  (begin
    ;; Only contract owner can remove managers
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Remove the cache manager
    (map-set cache-managers
      { manager: manager }
      { active: false }
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get a cache entry's information
(define-read-only (get-cache-entry (key (string-utf8 64)))
  (map-get? cache-entries { key: key })
)

;; Get cache performance metrics
(define-read-only (get-cache-performance (key (string-utf8 64)))
  (match (map-get? cache-entries { key: key })
    entry (let (
      (total-requests (+ (get hits entry) (get misses entry)))
      (hit-rate (if (> total-requests u0)
        (/ (* u100 (get hits entry)) total-requests)
        u0
      ))
    )
    {
      hits: (get hits entry),
      misses: (get misses entry),
      hit-rate: hit-rate,
      performance-tier: (calculate-performance-tier hit-rate)
    })
    none
  )
)

;; Get the total number of cache entries
(define-read-only (get-total-cache-entries)
  (var-get total-cache-entries)
)

;; Get total cache hits and misses
(define-read-only (get-cache-metrics)
  {
    total-hits: (var-get total-cache-hits),
    total-misses: (var-get total-cache-misses)
  }
)