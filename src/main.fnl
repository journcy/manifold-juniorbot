(local inspect (require "inspect"))
(local Manifold (require "manifold"))
(local Market Manifold.Market)

(local show #(-> $1 inspect print))

(fn log [...]
  (print (table.concat [...] " ")))

(fn ms->s [milliseconds]
  (math.floor (/ milliseconds 1000)))

(fn floor-divide [numerator denominator]
  "Returns (num // den, num % den)"
  (values (math.floor (/ numerator denominator)) 
          (% numerator denominator)))

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

; TODO: I literally just made this table up can we replace it with something
; more, uh, something?
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
  (Market:new {:yes mkt.pool.YES
               :no mkt.pool.NO
               :p mkt.p
               :t (get-days-until-resolution mkt)
               :id mkt.id
               :url mkt.url
               :question mkt.question}))

(local *market-cache* 
  (icollect [_ m (ipairs (let [(s markets-file) (pcall #(require "markets"))]
                           (if s markets-file
                             (M:get-all-markets))))]
    (when (and (= (. m :outcomeType) :BINARY)
               (not (. m :isResolved))) 
      (make-market m))))

(local *bets-cache*
  (let [(s bets-file) (pcall #(require "bets"))]
    (if s bets-file
      (M:get-bets { :username (. (M:get-authenticated-user) :username) }))))

(local *indexed-market-cache*
  (accumulate [index {}
               _ m (ipairs *market-cache*)]
    (do (tset index (. m :id) m) index)))

(fn get-all-investments [])

(fn get-portfolio-value [])

(fn get-balance []
  (or (?. (M:get-authenticated-user) :balance) 0))

(fn get-net-worth []
  (let [balance (get-balance)
        investments (get-portfolio-value)]
    (+ balance investments)))

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

; TODO: Double check that prices/etc. haven't changed before we actually do the
; buy
(fn place-bet [mkt outcome amount]
  (log "Buying" amount outcome "on" mkt.question)
  (M:bet {:contract mkt.id
          :outcome outcome
          :amount amount}))

(fn make-buy [mkt amount]
  (let [prob (mkt:prob)
        outcome (if (> prob 0.50) :YES :NO)]
    (place-bet mkt outcome amount)))

; TODO: Divide the money more intelligently to maximize returns.
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

(fn main []
  (rank-all-markets)
  (spend-balance *market-cache*))

(main)
