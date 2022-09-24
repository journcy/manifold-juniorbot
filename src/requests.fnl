(local http (require "http.request"))
; (local deferred (require "deferred"))

(local requests {})

(fn construct-query-string [query]
  (accumulate [params ""
               k v (pairs query)]
    (.. (if (= params "") (.. "?") (.. params "&"))
        (.. k "=" v))))

(fn requests.request [method url options]
  (let [params (construct-query-string (or options.query {}))
        req (http.new_from_uri (.. url params))
        req-headers (or options.headers {})]
    (tset req-headers ":method" method)
    (each [k v (pairs req-headers)]
      (req.headers:upsert (string.lower k) v))
    (when (not= options.body nil)
      (req:set_body options.body))
    (let [(headers stream) (assert (req:go))
          body (assert (stream:get_body_as_string))
          status (headers:get ":status")]
      (when (not= status "200")
        (error (.. (req:to_uri) ": " status " Error")))
      (if (not= options.parse nil)
        (options.parse body)
        body))))

requests
