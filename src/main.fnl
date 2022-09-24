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

; (show (. *market-cache* 9))
; (show (score-market (. *market-cache* 4)))
(print "START")
(print "-----")
(print)
(rank-all-markets)
(for [i 1 10] (let [mkt (. *market-cache* i) (s l p r t) (score-market mkt)] (show mkt) (show [s l p r t])))
(print)
(print "---")
(print "END")


; (show
;   [(# (icollect [_ m (ipairs *market-cache*)]
;                 (if (?. m :isResolved) true nil)))
;    (# (icollect [_ m (ipairs *market-cache*)]
;                 (if (not (?. m :isResolved)) true nil)))])
; (show (icollect [_ m (ipairs *market-cache*)]
;                 { :resolved (. m :isResolved)
;                   :question (. m :question)
;                   :url (. m :url) }))

; (local bets (M:get-bets { :username "journcy" }))

; (show (# *bets-cache*))
; (let [bets-resolved (icollect [_ b (ipairs *bets-cache*)]
;                               (. *indexed-market-cache* (. b :contractId) :isResolved))]
;   (show [(# (icollect [_ b (ipairs bets-resolved)] (if b b nil))) (# (icollect [_ b (ipairs bets-resolved)] (if b nil b)))]))
; (show (icollect [_ b (ipairs *bets-cache*)]
;                 (let [m (. *indexed-market-cache* (. b :contractId))]
;                   (when (not (. m :isResolved)) m))))

(comment (show ))

; (show (M:get-bets { :username "journcy" }))
; (show (os.date "%c" (ms->s 1642999445792)))
; (show (os.date "%c" (ms->s 1663938153978)))
; (show (M:get-market-by-id "pG3hOMmZlDv3PR3CLyi0"))
; (show (M:get-market "will-the-dc-trucker-convoy-prevent"))

; (show (M:get-authenticated-user))
; (show (M:get-user-by-id "7uH1XOw7dAcuF2AbQRBZVPl7JLJ2"))
; (show (M:get-markets { :limit 10 }))
; (show (# (M:get-all-markets)))

; (show [(p->risk 0.50)
;        (p->risk 0.45)
;        (p->risk 0.35)
;        (p->risk 0.11)
;        (p->risk 0.06)
;        (p->risk 0.02)
;        (p->risk 0.005)])
; -> { 0.5, 0.445, 0.335, 0.087, 0.0333, 0.0075, 0.0025 }

; (show (M:get-market "will-us-regulators-instruct-manifol"))

; (show (M.market-prob 0.206141 1068.53 957.028))
; (show (M.new-yes 979.019 0.206141 957.028))

; (let [market (Market:new { :yes 1072.49 :no 956.109 :p 0.206141 })]
;   (show {
;     "preprob" (market:prob)
;     "shares" (market:order :yes 1)
;     "prob" (-> (market:order :yes 1) (#(: $2 :prob))) }))

; (-> (Market:new { :yes 1068.53 :no 957.028 :p 0.206141 })
;     (: :prob)
;     print)

; (show (# (M:get-markets)))
; (show (# (M:get-all-markets)))
