(local json (require "json"))
(local requests (require "requests"))

(fn table-append [t1 t2]
  "Appends the contents of t1 to t2, modifying t2, and returns t2."
  (table.move t1 1 (# t1) (+ 1 (# t2)) t2))

(local Manifold { :BASE_URI "https://manifold.markets/api/v0" })
(fn Manifold.new [self o]
  (var obj (or o {}))
  (setmetatable obj self)
  (set self.__index self)
  obj)

;; See https://docs.manifold.markets/api

(fn Manifold.request [self method route options]
  (let [options (or options {})
        headers {}]
    (var body options.body)
    (when options.authenticated
      (assert (~= self.api_key nil) "You must provide a valid API key to make authenticated requests.")
      (tset headers :Authorization (.. "Key " self.api_key)))
    (when (~= options.body nil)
      (set body (json.encode body))
      (tset headers :Content-Type "application/json"))
    (requests.request method (.. self.BASE_URI route)
                      {:query options.query
                       :headers headers
                       :body body
                       :parse json.decode})))

(fn pagination-helper [request-func responses before limit]
  (let [limit (or limit 1000)
        more-responses (request-func { :limit limit :before before })
        rsps-received (# more-responses)]
    (if (> rsps-received 0)
      (pagination-helper 
        request-func
        (table-append more-responses responses)
        (?. more-responses rsps-received :id))
      responses)))


;; User queries

(fn Manifold.get-user [self username]
  "GET /v0/user/[username]"
  (self:request "GET" (.. "/user/" username)))

(fn Manifold.get-users [self]
  "GET /v0/users"
  (self:request "GET" "/users"))

(fn Manifold.get-user-by-id [self id]
  "GET /v0/user/by-id/[id]"
  (self:request "GET" (.. "/user/by-id/" id)))

(fn Manifold.get-authenticated-user [self]
  "GET /v0/me"
  (self:request "GET" "/me" { :authenticated true }))


;; Group queries

(fn Manifold.get-group [self slug]
  "GET /v0/group/[slug]"
  (self:request "GET" (.. "/group/" slug)))

(fn Manifold.get-groups [self]
  "GET /v0/groups"
  (self:request "GET" "/groups"))

(fn Manifold.get-group-by-id [self id]
  "GET /v0/group/by-id/[id]"
  (self:request "GET" (.. "/group/by-id/" id)))


;; Market queries

(fn Manifold.get-market [self slug]
  "GET /v0/slug/[marketSlug]"
  (self:request "GET" (.. "/slug/" slug)))

(fn Manifold.get-markets [self options]
  "GET /v0/markets"
  (let [options (or options {})]
    (self:request "GET" "/markets" 
                  {:query {:limit options.limit
                           :before options.before}})))

(fn Manifold.get-market-by-id [self id]
  "GET /v0/market/[marketId]"
  (self:request "GET" (.. "/market/" id)))

(local *markets-request-limit* 1000)
(fn Manifold.get-all-markets [self]
  "Repeatedly get markets until all have been fetched."
  (pagination-helper (partial self.get-markets self) [] nil *markets-request-limit*))


;; Bet queries

(fn Manifold.get-bets [self options]
  "GET /v0/bets"
  (let [options (or options {})]
    (self:request "GET" "/bets" 
                  {:query {:username options.username
                           :market options.market
                           :limit options.limit
                           :before options.before}})))


;; Buying and selling

(fn Manifold.bet [self options]
  "POST /v0/bet"
  (assert (and options.amount options.contract options.outcome))
  (self:request "POST" "/bet" 
                {:authenticated true
                 :body {:amount options.amount
                        :contractId options.contract
                        :outcome options.outcome
                        :limitProb options.limit-prob}}))

(fn Manifold.sell [self id options]
  "POST /v0/market/[marketId]/sell"
  (let [options (or options {})]
    (self:request "POST" (.. "/market/" id "/sell") 
                  {:authenticated true
                   :body {:outcome options.outcome
                          :shares options.share}})))


;; Managing markets

(fn Manifold.create-market [self options]
  "POST /v0/market"
  (assert (and options.outcome-type options.question options.description options.close-time))
  (assert (and (= options.outcome-type "BINARY") options.initial-prob))
  (assert (and (= options.outcome-type "NUMERIC") options.min options.max))
  (self:request "POST" "/market" 
                {:authenticated true
                 :body {:outcomeType options.outcome-type
                        :question options.question
                        :description options.description
                        :closeTime options.close-time
                        :tags options.tags
                        :initialProb options.initial-prob
                        :min options.min
                        :max options.max}}))

(fn Manifold.resolve-market [self id options]
  "POST /v0/market/[marketId]/resolve"
  (assert (and options.outcome))
  (self:request "POST" (.. "/market/" id "/resolve") 
                {:authenticated true
                 :body {:outcome options.outcome
                        :probabilityInt options.probability-int
                        :resolutions options.resolutions
                        :value options.value}}))


;; Implement Maniswap
; See https://manifoldmarkets.notion.site/Maniswap-ce406e1e897d417cbd491071ea8a0c39
; See https://docs.manifold.markets/market-details

(local Market { :yes 100.0 :no 100.0 :p 0.50 })
(fn Market.new [self o]
  (var obj (or o {}))
  (setmetatable obj self)
  (set self.__index self)
  obj)

(fn Market.prob [self]
  "Returns the market's YES probability. P = pn/(pn + (1-p)y)."
  (/ (* self.p self.no)
     (+ (* self.p self.no)
        (* (- 1 self.p) self.yes))))

(fn Market.k [self]
  "Get the k constant for a market. y^p*n^(1-p)=k."
  (let [ly (math.log self.yes)
        ln (math.log self.no)]
    (math.exp (+ (* self.p ly) (* (- 1 self.p) ln)))))

(fn new-yes [lk p n]
  (let [ln (math.log n)]
    (-> (/ lk p) (- (/ ln p)) (+ ln) math.exp)))

(fn new-no [lk p y]
  (let [ly (math.log y)
        p1 (- 1 p)]
    (-> (/ lk p1) (- (* (/ p p1) ly)) math.exp)))

(fn Market.rebalance [self share amt]
  "'Rebalances' a market using a new provided YES or NO share count."
  (assert (or (= share :yes) (= share :no)))
  (let [lk (math.log (self:k))
        new-share ((match share :yes new-no :no new-yes) lk self.p amt)]
    (Market:new {:yes (if (= share :no)  new-share amt)
                 :no  (if (= share :yes) new-share amt)
                 :p   self.p})))

(fn Market.order [self share amt]
  "Determine count of shares purchased for an amount of money and new market state."
  (assert (or (= share :yes) (= share :no)))
  (let [other-share (match share :yes :no :no :yes)
        new-share (+ (. self other-share) amt)
        new-market (self:rebalance other-share new-share)
        delta (- (. self share) (. new-market share))]
    (values (+ amt delta) new-market)))

; TODO: adding & removing liquidity
; TODO: add more market types?

(tset Manifold :Market Market)

Manifold
