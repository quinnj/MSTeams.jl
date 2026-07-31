function parse_activity(req::HTTP.Request)
    body = String(req.body)
    isempty(body) && throw(MSTeamsRequestError("Request body is empty"))
    try
        return JSON.parse(body, JSON.Object)
    catch err
        throw(MSTeamsRequestError("Invalid JSON payload"))
    end
end

function handle_activity_async(client::Union{Nothing, BotClient}, activity::AbstractDict, handler::Function, logger::AbstractLogger)
    response = handler(activity)
    response === nothing && return
    if client === nothing
        @warn "Handler returned response but no client was provided"
        return
    end
    if response isa AbstractString
        reply_text(client, activity, response)
        return
    end
    if response isa AbstractDict
        reply_activity(client, activity, response)
        return
    end
    throw(ArgumentError("Handler must return nothing, string, or dict"))
end

function build_server_handler(handler::Function; client::Union{Nothing, BotClient}=nothing, path::AbstractString="/api/messages", health_path::AbstractString="/healthz", logger::Union{Nothing, AbstractLogger}=nothing)
    logger_value = logger === nothing ? Logging.global_logger() : logger
    path_value = String(path)
    health_value = String(health_path)
    return function (req::HTTP.Request)
        req_path = String(HTTP.URI(req.target).path)
        method = uppercase(String(req.method))
        if method == "GET" && req_path == health_value
            return HTTP.Response(200, "ok")
        end
        req_path != path_value && return HTTP.Response(404, "not found")
        method != "POST" && return HTTP.Response(405, "method not allowed")
        activity = try
            parse_activity(req)
        catch err
            err isa MSTeamsRequestError && return HTTP.Response(400, err.message)
            return HTTP.Response(400, "invalid request")
        end
        errormonitor(Threads.@spawn handle_activity_async(client, activity, handler, logger_value))
        return HTTP.Response(200, "accepted")
    end
end

function start_server(handler::Function; host::AbstractString="0.0.0.0", port::Integer=3978, client::Union{Nothing, BotClient}=nothing, path::AbstractString="/api/messages", health_path::AbstractString="/healthz", logger::Union{Nothing, AbstractLogger}=nothing)
    server_handler = build_server_handler(handler; client=client, path=path, health_path=health_path, logger=logger)
    return HTTP.serve!(server_handler, host, port)
end

function run_server(handler::Function; host::AbstractString="0.0.0.0", port::Integer=3978, client::Union{Nothing, BotClient}=nothing, path::AbstractString="/api/messages", health_path::AbstractString="/healthz", logger::Union{Nothing, AbstractLogger}=nothing)
    server_handler = build_server_handler(handler; client=client, path=path, health_path=health_path, logger=logger)
    HTTP.serve(server_handler, host, port)
    return
end
