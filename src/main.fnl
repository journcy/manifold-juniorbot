(local inspect (require "inspect"))
(local Manifold (require "manifold"))
(local Market Manifold.Market)

(local show #(-> $1 inspect print))

(local M (Manifold:new { :api_key "" }))

(fn ms->s [milliseconds]
  (math.floor (/ milliseconds 1000)))

; TODO: I literally just made this table up can we replace it with something
; more, uh, something?
(local p->risk-table 
  { 0.50 0.50
    0.40 0.39
    0.30 0.28
    0.20 0.15
    0.10 0.08
    0.08 0.06
    0.05 0.02
    0.03 0.01
    0.01 0.005
    0.00 0.00 })
(local p->risk-keys
  [0.50 0.40 0.30 0.20 0.10 0.08 0.05 0.03 0.01])
(fn p->risk [p]
  "For a given prob, map it to a 'risk' by finding its upper and lower bounds
  in the keys of the risk table, then transforming the prob from the space of
  the preimage bounds to the image bounds. So, a prob halfway between e.g.,
  0.40 and 0.30 (that is, 0.35) ends up halfway between 0.39 and 0.28 (0.335)." 
  (if (> p 0.50) (- 1 (p->risk (- 1 p)))
    (let [[upper lower] 
          (accumulate 
            [bounds [0.50 0]
             _ k (ipairs p->risk-keys)]
            (let [[u l] bounds]
              (if (> p k l) [u k]
                (> u k p) [k l]
                (= p k)   [p p]
                [u l])))]
      (if (= upper lower) (. p->risk-table upper)
       (+ (. p->risk-table lower)
          (* (- (. p->risk-table upper)
                (. p->risk-table lower))
             (/ (- p lower)
                (- upper lower))))))))

(local *market-cache* 
  (icollect [_ m (ipairs (let [(s markets-file) (pcall #(require "markets"))]
                           (if s markets-file
                             (M:get-all-markets))))]
            (when (and (= (. m :outcomeType) :BINARY)
                  (not (. m :isResolved))) m)))
; (M:get-markets { :limit 100 })

(local *bets-cache*
  (let [(s bets-file) (pcall #(require "bets"))]
    (if s bets-file
      (M:get-bets { :username (. (M:get-authenticated-user) :username) }))))

(local *local-time* (os.time))

(local *indexed-market-cache*
  (accumulate [index {}
               _ m (ipairs *market-cache*)]
              (do (tset index (. m :id) m) index)))

(fn get-all-investments [])

(fn get-portfolio-value [mani])

(fn get-net-worth [mani]
  (let [balance (?. (mani:get-authenticated-user) :balance)
        investments (get-portfolio-value mani)]
    (+ balance investments)))

(fn get-time-until-resolution [mkt]
  (let [close-time (ms->s (. mkt :closeTime))]
    (os.difftime close-time *local-time*)))

(local *liquidity-weight* 1.0)
(local *price-weight* 1.0)
(local *risk-weight* 1.0)
(local *time-weight* (/ 1.0 60 60 24 10))
(fn score-market [mkt]
  (let [prob (. mkt :probability)
        dominant-share (if (> prob 0.50) :YES :NO)
        liquidity (. mkt :pool dominant-share)
        price (if (= dominant-share :YES) prob (- 1 prob))
        risk (p->risk price)
        time (get-time-until-resolution mkt)]
    (values (/ (* liquidity *liquidity-weight*)
               ; (* price *price-weight*)
               (* risk risk *risk-weight*)
               (* time *time-weight*))
            (* liquidity *liquidity-weight*)
            (* price *price-weight*)
            (* risk risk *risk-weight*)
            (* time *time-weight*))))

(fn rank-all-markets []
  (table.sort *market-cache*
    (fn [a b]
      (let [score-a (score-market a)
            score-b (score-market b)]
        (> score-a score-b)))))

(print "START")
(print "-----")
(print)
(rank-all-markets)
(for [i 1 10] 
  (let [mkt (. *market-cache* i) 
        (s l p r t) (score-market mkt)] 
    (show mkt) 
    (show [s l p r t])))
(print)
(print "---")
(print "END")
