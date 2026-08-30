--[[
File: network_retry_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies HTTP redirects, Retry-After, budgets, and replay closure.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency)
        return load_module(dependency, cache)
    end
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    local value = chunk()
    cache[name] = value
    return value
end

local MANIFEST = {
    identity = "tp006-modern-candidate-v1",
    maximum_count = 10,
    exponent = 2,
    maximum_delay_ms = 30000,
    runtime_wait_cap_ms = 60000,
    deterministic_jitter_permille = 100,
}

local function controller(network, overrides)
    local spec = {
        logical_request_id = "request-A",
        initial_url = "https://api.example/v1",
        retry_count = 2,
        base_delay_ms = 500,
        maximum_redirects = 3,
        logical_deadline_at = 100000,
        turn_deadline_at = 90000,
        runtime_deadline_at = 80000,
        manifest = MANIFEST,
    }
    for key, value in pairs(overrides or {}) do spec[key] = value end
    return assert(network.new_retry_controller(spec))
end

return {
    name = "fault/network-retry",
    cases = {
        {
            name = "HTTP header carrier selects final block and rejects ambiguity",
            run = function()
                local network = load_module("network")
                local bytes = table.concat({
                    "HTTP/1.1 100 Continue\r\n",
                    "X-Interim: yes\r\n\r\n",
                    "HTTP/2 429\r\n",
                    "Retry-After: 2\r\n",
                    "Content-Type: application/json\r\n\r\n",
                })
                local response = assert(network.parse_http_headers(bytes, {
                    maximum_bytes = 1024,
                    maximum_line_bytes = 128,
                    maximum_lines = 16,
                }))
                A.equal(response.version, "2")
                A.equal(response.status, 429)
                A.equal(assert(network.single_header(response, "retry-after")), "2")
                A.falsy(network.single_header(response, "x-interim"))
                A.raises(function() response.status = 200 end, "cannot be modified")

                local duplicated = assert(network.parse_http_headers(
                    "HTTP/1.1 503 Service Unavailable\r\n"
                        .. "Retry-After: 1\r\nRetry-After: 2\r\n\r\n",
                    {
                        maximum_bytes = 1024,
                        maximum_line_bytes = 128,
                        maximum_lines = 16,
                    }
                ))
                local value, duplicate_error = network.single_header(duplicated, "Retry-After")
                A.falsy(value)
                A.equal(duplicate_error.code, "AmbiguousHttpHeader")

                local malformed, malformed_error = network.parse_http_headers(
                    "HTTP/1.1 200 OK\nX: y\n\n",
                    {
                        maximum_bytes = 1024,
                        maximum_line_bytes = 128,
                        maximum_lines = 16,
                    }
                )
                A.falsy(malformed)
                A.equal(malformed_error.code, "InvalidHttpHeaders")
            end,
        },
        {
            name = "same-origin redirect fixture follows only 307 and 308",
            run = function()
                local network = load_module("network")
                local fixtures = assert(loadfile(
                    YACA_TEST_ROOT .. "/.develope-docs/contracts/fixtures/transport.lua",
                    "t",
                    _ENV
                ))().redirect_cases
                for _, fixture in ipairs(fixtures) do
                    local decision = assert(network.redirect_decision({
                        status = fixture.status,
                        source_url = fixture.from,
                        location = fixture.to,
                        redirect_count = 0,
                        maximum_redirects = 3,
                        history = { fixture.from },
                    }))
                    if fixture.automatic then
                        A.equal(decision.action, "follow", fixture.id)
                        A.equal(decision.key_reused, fixture.key_reused)
                    elseif fixture.status == 302 then
                        A.equal(decision.action, "none", fixture.id)
                    else
                        A.equal(decision.action, "reject", fixture.id)
                        A.falsy(decision.key_reused)
                    end
                end

                local relative = assert(network.redirect_decision({
                    status = 307,
                    source_url = "https://API.Example:443/a/b?old=1",
                    location = "../c?new=1#fragment",
                    redirect_count = 1,
                    maximum_redirects = 3,
                    history = { "https://api.example:443/a/b?old=1" },
                }))
                A.equal(relative.action, "follow")
                A.equal(relative.target_url, "https://api.example:443/c?new=1")
                A.equal(relative.origin, "https://api.example:443")

                local loop = assert(network.redirect_decision({
                    status = 308,
                    source_url = "https://api.example/a",
                    location = "/a",
                    redirect_count = 1,
                    maximum_redirects = 3,
                    history = { "https://api.example/a" },
                }))
                A.equal(loop.code, "RedirectLoop")

                local capped = assert(network.redirect_decision({
                    status = 307,
                    source_url = "https://api.example/a",
                    location = "/b",
                    redirect_count = 3,
                    maximum_redirects = 3,
                    history = { "https://api.example/a" },
                }))
                A.equal(capped.code, "RedirectLimit")
            end,
        },
        {
            name = "Retry-After delta and legacy date forms are UTC bounded",
            run = function()
                local network = load_module("network")
                A.equal(assert(network.parse_retry_after(" 2 ", 0, 60000)), 2000)
                local target = 784111777
                A.equal(assert(network.parse_retry_after(
                    "Sun, 06 Nov 1994 08:49:37 GMT",
                    target - 10,
                    60000
                )), 10000)
                A.equal(assert(network.parse_retry_after(
                    "Sunday, 06-Nov-94 08:49:37 GMT",
                    target - 10,
                    60000
                )), 10000)
                A.equal(assert(network.parse_retry_after(
                    "Sun Nov  6 08:49:37 1994",
                    target + 10,
                    60000
                )), 0)
                local invalid, invalid_error = network.parse_retry_after("tomorrow", 0, 60000)
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidRetryAfter")
                local over, over_error = network.parse_retry_after("61", 0, 60000)
                A.falsy(over)
                A.equal(over_error.code, "RetryAfterLimit")
            end,
        },
        {
            name = "deterministic retry vector matches the modern proof oracle",
            run = function()
                local network = load_module("network")
                local expected = {
                    ["request-A"] = {
                        550, 924, 1949, 3905, 7960, 16411, 30000, 30000, 27412, 30000,
                    },
                    ["request-B"] = {
                        509, 1066, 2118, 4270, 8012, 16556, 28278, 30000, 30000, 27617,
                    },
                }
                for request_id, delays in pairs(expected) do
                    for retry_number, delay in ipairs(delays) do
                        A.equal(assert(network.retry_delay_ms(
                            request_id,
                            retry_number,
                            500,
                            MANIFEST
                        )), delay)
                    end
                end
                A.equal(assert(network.retry_delay_ms(
                    "request-A",
                    10,
                    30000,
                    MANIFEST
                )), assert(network.retry_delay_ms(
                    "request-A",
                    10,
                    1 << 40,
                    MANIFEST
                )))
            end,
        },
        {
            name = "retry attempts honor local delay Retry-After and exact exhaustion",
            run = function()
                local network = load_module("network")
                local retry = controller(network)
                A.equal(assert(retry:start_attempt("a1", 0)).url, "https://api.example/v1")
                local first = assert(retry:finish_attempt("a1", {
                    category = "connect",
                }, 10))
                A.equal(first.action, "wait")
                A.equal(first.retry_number, 1)
                A.equal(first.local_delay_ms, 550)
                A.equal(first.resume_at, 560)
                local early, early_error = retry:start_attempt("a2", 559)
                A.falsy(early)
                A.equal(early_error.code, "RetryNotReady")
                A.equal(assert(retry:start_attempt("a2", 560)).retry_number, 1)
                local second = assert(retry:finish_attempt("a2", {
                    category = "http-503",
                    status = 503,
                    retry_after_ms = 2000,
                }, 600))
                A.equal(second.local_delay_ms, 924)
                A.equal(second.delay_ms, 2000)
                A.equal(second.resume_at, 2600)
                A.equal(assert(retry:start_attempt("a3", 2600)).attempt_number, 3)
                local exhausted = assert(retry:finish_attempt("a3", {
                    category = "dns",
                }, 2610))
                A.equal(exhausted.action, "finish")
                A.equal(exhausted.code, "RetryExhausted")
                A.equal(exhausted.attempts, 3)
                A.equal(retry:status().state, "terminal")
            end,
        },
        {
            name = "first canonical event permanently closes automatic replay",
            run = function()
                local network = load_module("network")
                local retry = controller(network)
                retry:start_attempt("event-1", 0)
                A.equal(assert(retry:observe_canonical_event("event-1", 10)), 1)
                local decision = assert(retry:finish_attempt("event-1", {
                    category = "connect",
                }, 20))
                A.equal(decision.action, "finish")
                A.equal(decision.code, "CanonicalEventReplayForbidden")
                A.equal(decision.canonical_events, 1)
                A.falsy(retry:pending())
                local replay, replay_error = retry:start_attempt("event-2", 21)
                A.falsy(replay)
                A.equal(replay_error.code, "RetryState")
            end,
        },
        {
            name = "controller applies the frozen retry matrix without hidden fallbacks",
            run = function()
                local network = load_module("network")
                local fixtures = assert(loadfile(
                    YACA_TEST_ROOT .. "/.develope-docs/contracts/fixtures/transport.lua",
                    "t",
                    _ENV
                ))().retry_cases
                local category_by_id = {
                    ["dns-before-event"] = "dns",
                    ["connect-before-event"] = "connect",
                    ["http-429-before-event"] = "http-429",
                    ["http-503-before-event"] = "http-503",
                    ["event-observed"] = "connect",
                    auth = "auth-4xx",
                    ["tls-verification"] = "tls-verification",
                    protocol = "protocol",
                    cancel = "cancel",
                    unknown = "outcome-unknown",
                }
                for _, fixture in ipairs(fixtures) do
                    local retry = controller(network)
                    retry:start_attempt("matrix-1", 0)
                    if fixture.canonical_events > 0 then
                        retry:observe_canonical_event("matrix-1", 1)
                    end
                    local decision = assert(retry:finish_attempt("matrix-1", {
                        category = category_by_id[fixture.id],
                    }, 2))
                    A.equal(decision.action == "wait", fixture.automatic, fixture.id)
                end
            end,
        },
        {
            name = "same-origin redirect becomes a fresh attempt but cross-origin does not",
            run = function()
                local network = load_module("network")
                local retry = controller(network)
                retry:start_attempt("redirect-1", 0)
                local redirect = assert(retry:finish_attempt("redirect-1", {
                    category = "completed",
                    status = 307,
                    location = "/v2",
                }, 10))
                A.equal(redirect.kind, "redirect")
                A.equal(redirect.delay_ms, 0)
                A.truthy(redirect.key_reused)
                local admitted = assert(retry:start_attempt("redirect-2", 10))
                A.equal(admitted.url, "https://api.example/v2")
                A.equal(admitted.redirect_count, 1)
                A.equal(assert(retry:finish_attempt("redirect-2", {
                    category = "completed",
                }, 20)).outcome, "completed")

                local blocked = controller(network)
                blocked:start_attempt("blocked-1", 0)
                local rejected = assert(blocked:finish_attempt("blocked-1", {
                    category = "completed",
                    status = 308,
                    location = "https://other.example/v2",
                }, 10))
                A.equal(rejected.code, "CrossOriginRedirect")
                A.equal(blocked:status().state, "terminal")
            end,
        },
        {
            name = "deadline budget and cancel close waits without ghost attempts",
            run = function()
                local network = load_module("network")
                local budget = controller(network, {
                    logical_deadline_at = 500,
                    turn_deadline_at = 1000,
                    runtime_deadline_at = 1000,
                })
                budget:start_attempt("budget-1", 0)
                local exhausted = assert(budget:finish_attempt("budget-1", {
                    category = "connect",
                }, 10))
                A.equal(exhausted.code, "RetryBudgetExceeded")
                A.falsy(budget:pending())

                local waiting = controller(network)
                waiting:start_attempt("wait-1", 0)
                A.equal(assert(waiting:finish_attempt("wait-1", {
                    category = "dns",
                }, 10)).action, "wait")
                local cancelled = assert(waiting:cancel(11))
                A.equal(cancelled.outcome, "cancelled")
                A.falsy(cancelled.cancel_active)
                local ghost, ghost_error = waiting:start_attempt("wait-2", 1000)
                A.falsy(ghost)
                A.equal(ghost_error.code, "RetryState")

                local active = controller(network)
                active:start_attempt("active-1", 0)
                A.truthy(assert(active:cancel(1)).cancel_active)
                local regressed, regression_error = active:cancel(0)
                A.falsy(regressed)
                A.equal(regression_error.code, "InvalidMonotonicTime")
            end,
        },
        {
            name = "body-unknown protocol auth refusal and user cancel are terminal",
            run = function()
                local network = load_module("network")
                local expected = {
                    ["body-outcome-unknown"] = "unknown",
                    ["outcome-unknown"] = "unknown",
                    ["tls-verification"] = "failed",
                    ["auth-4xx"] = "failed",
                    ["ordinary-4xx"] = "failed",
                    protocol = "failed",
                    ["content-refusal"] = "failed",
                    cancel = "cancelled",
                }
                for category, outcome in pairs(expected) do
                    local retry = controller(network)
                    retry:start_attempt("terminal-1", 0)
                    local decision = assert(retry:finish_attempt("terminal-1", {
                        category = category,
                    }, 1))
                    A.equal(decision.action, "finish")
                    A.equal(decision.outcome, outcome)
                    A.equal(decision.retries, 0)
                end
            end,
        },
    },
}
