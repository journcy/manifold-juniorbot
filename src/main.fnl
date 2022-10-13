(local inspect (require "inspect"))
(local Manifold (require "manifold"))
(local Market Manifold.Market)

(local show #(-> $1 inspect print))

(fn log [...]
  (print (table.concat [(os.date "%F %T") "|" ...] " ")))

(fn ms->s [milliseconds]
  (math.floor (/ milliseconds 1000)))

(fn floor-divide [numerator denominator]
  "Returns (num // den, num % den)"
  (values (math.floor (/ numerator denominator)) 
          (% numerator denominator)))

(fn table-has [t e]
  "Returns true if the element e is in the table t, false otherwise."
  (accumulate [result false
               _ v (ipairs t)
               &until result]
    (= e v)))

(fn find-nearest-bounds [space v]
  "space is a descending-sorted table of numbers, v is a number. Returns the
  two consecutive values of space that v is bounded most closely by, space[1]
  if v > space[1], space[-1] if v < space[-1], and space[i] if v == space[i]."
  (let [first (. space 1)
        last (. space (# space))]
    (accumulate [bounds [first last]
                 _ k (ipairs space)]
      (let [[u l] bounds]
        (if (> v k l) [u k]
          (> u k v) [k l]
          (= v k)   [v v]
          [u l])))))

(local p->risk-table 
  {0.50 0.50
   0.40 0.39
   0.30 0.28
   0.20 0.15
   0.10 0.08
   0.08 0.06
   0.05 0.02
   0.03 0.01
   0.01 0.005
   0.00 0.00})
(local p->risk-keys
  [0.50 0.40 0.30 0.20 0.10 0.08 0.05 0.03 0.01 0.00])
(fn p->risk [p]
  "For a given prob, map it to a 'risk' by finding its upper and lower bounds
  in the keys of the risk table, then transforming the prob from the space of
  the preimage bounds to the image bounds. So, a prob halfway between e.g.,
  0.40 and 0.30 (that is, 0.35) ends up halfway between 0.39 and 0.28 (0.335)." 
  (if (> p 0.50) (p->risk (- 1 p))
    (let [[upper lower] (find-nearest-bounds p->risk-keys p)]
      (if (= upper lower) 
        (. p->risk-table upper)
        (+ (. p->risk-table lower)
           (* (- (. p->risk-table upper)
                 (. p->risk-table lower))
              (/ (- p lower)
                 (- upper lower))))))))

(local *local-time* (os.time))
(local *seconds-in-a-day* (* 60 60 24))
(fn get-days-until-resolution [mkt]
  (let [close-time (ms->s (. mkt :closeTime))]
    (/ (os.difftime close-time *local-time*)
       *seconds-in-a-day*)))

(local *api-key* (or (os.getenv "MANIFOLD_API_KEY") 
                     (error "You must set $MANIFOLD_API_KEY.")))
(local M (Manifold:new { :api_key *api-key* }))

(fn make-market [mkt]
  (tset mkt :yes mkt.pool.YES)
  (tset mkt :no  mkt.pool.NO)
  (tset mkt :t (get-days-until-resolution mkt))
  ;; The Market class also relies on the :p property, but Manifold returns it
  ;; like that by default, so we'll make the questionable decision not to set
  ;; it ourselves. I want all the extra properties for future development.
  (Market:new mkt))

;; TODO: Would be nice to also check the market description. We'd have to fetch
;; the markets individually, though.
;; TODO: There's a group for self-resolving markets--we don't seem to get group
;; info right now, though. Would be good to use in addition to the rest.
(fn mkt-resolves-prob? [mkt]
  "Heuristic function to detect markets that resolve PROB. We'll basically
  always lose money on these, so let's exclude them from the list."
  (let [clean-question (string.upper (. mkt :question))
        ;; The given text, with at least one non-letter character on each side
        ;; (so as to not false positive on substrings of words).
        ;; See https://www.lua.org/manual/5.1/manual.html#5.4.1
        has-mkt-pattern "[^%u]MKT[^%u]"
        has-prob-pattern "[^%u]PROB[^%u]"
        has-self-resolve-pattern "[^%u]SELF-RESOLVING[^%u]"]
    (not (and (= (string.find clean-question has-mkt-pattern) nil)
              (= (string.find clean-question has-prob-pattern) nil)
              (= (string.find clean-question has-self-resolve-pattern) nil)))))

(comment "Testing mkt-resolves-prob?."
         ;; I eval this table in my editor to check the tests.
         ;; TODO: Maybe add real testing at some point?
         [(= true  (mkt-resolves-prob? { :question "Is resolve to mkt bad? [resolve to mkt]" }))
          (= true  (mkt-resolves-prob? { :question "What are the best ways to operate a self-resolving (resolve-to-MKT) question?" }))
          (= true  (mkt-resolves-prob? { :question "How many markets will be created next week, with daily free markets just removed? (prob=count/300)" }))
          (= false (mkt-resolves-prob? { :question "Will Manifold allow users to set an initial probability on paid markets?" }))
          (= false (mkt-resolves-prob? { :question "Will Raub make it to Capo Deli by 11:07pm ET?" }))])

;; See https://manifold.markets/NotMyPresident/juniorbot-trap
;; TODO: Come up with a better way to avoid "trap" markets like this. Maybe
;; look for activity? Normally highly liquid markets should have lots of
;; traders.
(local *creator-blacklist* 
  {"NotMyPresident" true ; See Junior trap market. He did tip me back though
   "dreev" true ; I'm sorry dreev you just make too many PROB markets
   })
(fn mkt-creator-blacklisted? [mkt]
  (if (not= (?. *creator-blacklist* (. mkt :creatorUsername)) nil)
    true false))

(fn include-market? [mkt]
  (and (= (. mkt :outcomeType) :BINARY)
       (not (. mkt :isResolved))
       (not (mkt-creator-blacklisted? mkt)) 
       (not (mkt-resolves-prob? mkt))))

(local *market-cache* 
  (let [(success markets-file) (pcall #(require "markets"))
        markets (if success markets-file (M:get-all-markets))]
   (icollect [_ mkt (ipairs markets)]
     (if (include-market? mkt) (make-market mkt) nil))))

;; Bets cache currently not in use
; (local *bets-cache*
;   (let [(s bets-file) (pcall #(require "bets"))]
;     (if s bets-file
;       (M:get-bets { :username (. (M:get-authenticated-user) :username) }))))

;; ID-indexed market cache currently not in use
; (local *indexed-market-cache*
;   (accumulate [index {}
;                _ m (ipairs *market-cache*)]
;     (do (tset index (. m :id) m) index)))

; (fn get-all-investments [])

; (fn get-portfolio-value [])

(fn get-balance []
  (or (?. (M:get-authenticated-user) :balance) 0))

; (fn get-net-worth []
;   (let [balance (get-balance)
;         investments (get-portfolio-value)]
;     (+ balance investments)))

(fn score-market [mkt]
  (let [prob (mkt:prob)
        price (if (> prob 0.50) prob (- 1 prob))
        risk (- 1 (p->risk price))
        liquidity (mkt:k)
        time mkt.t]
    (values (/ (* liquidity price risk)
               (* (- 1 risk) time))
            liquidity price risk time)))

(fn rank-all-markets []
  (table.sort *market-cache*
              (fn [a b]
                (let [score-a (score-market a)
                      score-b (score-market b)]
                  (> score-a score-b)))))

;; TODO: Double check that prices haven't changed before we place orders
;; TODO: Add a flag or something to enable dry runs
(local *dry-run* false)
(fn place-bet [mkt outcome amount]
  (log "Buying" amount outcome "on" mkt.question)
  (when (not *dry-run*)
    (M:bet {:contract mkt.id
            :outcome outcome
            :amount amount})))

(fn make-buy [mkt amount]
  (let [prob (mkt:prob)
        outcome (if (> prob 0.50) :YES :NO)]
    (place-bet mkt outcome amount)))

(local *buying-increment* 100)
(fn spend-balance [markets]
  (let [balance (get-balance)
        (incr-to-spend last-incr) (floor-divide balance *buying-increment*)
        mkt-count (# markets)]
    (log "Found M$" balance "to spend across" 
         (+ incr-to-spend (if (> last-incr 0) 1 0)) "markets.")
    (if (> incr-to-spend 0) 
      (for [i 1 incr-to-spend] 
        (make-buy (. markets i) *buying-increment*)))
    (if (> last-incr 0)
      (make-buy (. markets (+ incr-to-spend 1)) last-incr))
    (if (= incr-to-spend last-incr 0) (log "No balance to spend!"))))

;; TODO: Calculate portfolio value and sell out of low-return shares to free up cash
;; TODO: Account for new flat trading fee in market math code
;; TODO: Divide invested money intelligently to maximize returns
;; TODO: Calculate the "risk" curve from past market resolution data

(fn main []
  (rank-all-markets)
  (spend-balance *market-cache*))

(main)
