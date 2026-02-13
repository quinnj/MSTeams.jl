const DEFAULT_TOKEN_URL = "https://login.microsoftonline.com/botframework.com/oauth2/v2.0/token"
const DEFAULT_TOKEN_SCOPE = "https://api.botframework.com/.default"
const TOKEN_EXPIRY_SKEW_SECONDS = 60

mutable struct BotToken
    access_token::String
    expires_at::DateTime
end

mutable struct BotClient
    app_id::String
    app_password::String
    token_url::String
    scope::String
    logger::AbstractLogger
    token::Union{Nothing, BotToken}
end

function BotClient(; app_id::AbstractString, app_password::AbstractString, token_url::AbstractString=DEFAULT_TOKEN_URL, scope::AbstractString=DEFAULT_TOKEN_SCOPE, logger::Union{Nothing, AbstractLogger}=nothing)
    app_id_value = strip(String(app_id))
    app_password_value = strip(String(app_password))
    isempty(app_id_value) && throw(MSTeamsConfigurationError("app_id is required"))
    isempty(app_password_value) && throw(MSTeamsConfigurationError("app_password is required"))
    logger_value = logger === nothing ? Logging.global_logger() : logger
    return BotClient(app_id_value, app_password_value, String(token_url), String(scope), logger_value, nothing)
end

function token_expired(token::BotToken)
    return Dates.now(Dates.UTC) >= token.expires_at
end

function get_access_token(client::BotClient)
    client.token !== nothing && !token_expired(client.token) && return client.token.access_token
    body = form_encode(Dict(
        "grant_type" => "client_credentials",
        "client_id" => client.app_id,
        "client_secret" => client.app_password,
        "scope" => client.scope,
    ))
    headers = Dict("Content-Type" => "application/x-www-form-urlencoded")
    response = HTTP.post(client.token_url; headers=headers, body=body)
    status = Int(response.status)
    status >= 300 && throw(MSTeamsAuthError("Failed to obtain access token"))
    payload = JSON.parse(HTTP.payload(response), JSON.Object)
    access_token = get(() -> nothing, payload, "access_token")
    expires_in = get(() -> nothing, payload, "expires_in")
    access_token === nothing && throw(MSTeamsAuthError("Token response missing access_token"))
    expires_in === nothing && throw(MSTeamsAuthError("Token response missing expires_in"))
    expiry_seconds = max(Int(expires_in) - TOKEN_EXPIRY_SKEW_SECONDS, 0)
    expires_at = Dates.now(Dates.UTC) + Dates.Second(expiry_seconds)
    client.token = BotToken(String(access_token), expires_at)
    return client.token.access_token
end

function activity_url(service_url::AbstractString, conversation_id::AbstractString; reply_to_id=nothing)
    base = normalize_url(service_url)
    conversation_value = HTTP.URIs.escapeuri(String(conversation_id))
    if reply_to_id === nothing
        return "$(base)/v3/conversations/$(conversation_value)/activities"
    end
    reply_value = HTTP.URIs.escapeuri(String(reply_to_id))
    return "$(base)/v3/conversations/$(conversation_value)/activities/$(reply_value)"
end

function should_parse_json(headers::Dict{String, String}, body::AbstractVector{UInt8})
    content_type = lowercase(get(() -> get(() -> "", headers, "content-type"), headers, "Content-Type"))
    occursin("json", content_type) && return true
    isempty(body) && return false
    for byte in body
        if byte == UInt8('\n') || byte == UInt8('\r') || byte == UInt8(' ') || byte == UInt8('\t')
            continue
        end
        return byte == UInt8('{') || byte == UInt8('[')
    end
    return false
end

function parse_response_body(headers::Dict{String, String}, body::AbstractVector{UInt8})
    should_parse_json(headers, body) || return body
    return JSON.parse(body, JSON.Object)
end

function send_activity(client::BotClient, service_url::AbstractString, conversation_id::AbstractString, activity::AbstractDict; reply_to_id=nothing)
    url = activity_url(service_url, conversation_id; reply_to_id=reply_to_id)
    token = get_access_token(client)
    headers = Dict("Authorization" => "Bearer $(token)", "Content-Type" => "application/json")
    response = HTTP.post(url; headers=headers, body=JSON.json(activity))
    status = Int(response.status)
    status >= 300 && throw(MSTeamsResponseError("Connector API returned error", status))
    return parse_response_body(Dict(response.headers), HTTP.payload(response))
end

function build_message_activity(; text::AbstractString, from=nothing, recipient=nothing, conversation=nothing, channel_id=nothing, reply_to_id=nothing, entities=nothing, attachments=nothing, channel_data=nothing)
    payload = JSON.Object(
        "type" => "message",
        "text" => String(text),
    )
    from !== nothing && (payload["from"] = to_object(from))
    recipient !== nothing && (payload["recipient"] = to_object(recipient))
    conversation !== nothing && (payload["conversation"] = to_object(conversation))
    channel_id !== nothing && (payload["channelId"] = String(channel_id))
    reply_to_id !== nothing && (payload["replyToId"] = String(reply_to_id))
    entities !== nothing && (payload["entities"] = entities)
    attachments !== nothing && (payload["attachments"] = attachments)
    channel_data !== nothing && (payload["channelData"] = channel_data)
    return payload
end

function reply_text(client::BotClient, activity::AbstractDict, text::AbstractString)
    service_url = get(() -> nothing, activity, "serviceUrl")
    conversation = get(() -> nothing, activity, "conversation")
    reply_to_id = get(() -> nothing, activity, "id")
    service_url === nothing && throw(MSTeamsRequestError("Activity missing serviceUrl"))
    conversation === nothing && throw(MSTeamsRequestError("Activity missing conversation"))
    conversation_id = get(() -> nothing, conversation, "id")
    conversation_id === nothing && throw(MSTeamsRequestError("Conversation missing id"))
    payload = build_message_activity(
        text=text,
        from=get(() -> nothing, activity, "recipient"),
        recipient=get(() -> nothing, activity, "from"),
        conversation=conversation,
        channel_id=get(() -> nothing, activity, "channelId"),
        reply_to_id=reply_to_id,
    )
    return send_activity(client, String(service_url), String(conversation_id), payload; reply_to_id=reply_to_id)
end

function reply_activity(client::BotClient, activity::AbstractDict, response_activity::AbstractDict)
    service_url = get(() -> nothing, activity, "serviceUrl")
    conversation = get(() -> nothing, activity, "conversation")
    reply_to_id = get(() -> nothing, activity, "id")
    service_url === nothing && throw(MSTeamsRequestError("Activity missing serviceUrl"))
    conversation === nothing && throw(MSTeamsRequestError("Activity missing conversation"))
    conversation_id = get(() -> nothing, conversation, "id")
    conversation_id === nothing && throw(MSTeamsRequestError("Conversation missing id"))
    payload = JSON.Object(response_activity)
    get(() -> nothing, payload, "type") === nothing && (payload["type"] = "message")
    get(() -> nothing, payload, "from") === nothing && (payload["from"] = get(() -> nothing, activity, "recipient"))
    get(() -> nothing, payload, "recipient") === nothing && (payload["recipient"] = get(() -> nothing, activity, "from"))
    get(() -> nothing, payload, "conversation") === nothing && (payload["conversation"] = conversation)
    get(() -> nothing, payload, "channelId") === nothing && (payload["channelId"] = get(() -> nothing, activity, "channelId"))
    get(() -> nothing, payload, "replyToId") === nothing && (payload["replyToId"] = reply_to_id)
    return send_activity(client, String(service_url), String(conversation_id), payload; reply_to_id=reply_to_id)
end

function send_message(client::BotClient; service_url::AbstractString, conversation_id::AbstractString, text::AbstractString, from=nothing, recipient=nothing, channel_id=nothing, reply_to_id=nothing, entities=nothing, attachments=nothing, channel_data=nothing)
    payload = build_message_activity(
        text=text,
        from=from,
        recipient=recipient,
        conversation=JSON.Object("id" => String(conversation_id)),
        channel_id=channel_id,
        reply_to_id=reply_to_id,
        entities=entities,
        attachments=attachments,
        channel_data=channel_data,
    )
    return send_activity(client, service_url, conversation_id, payload; reply_to_id=reply_to_id)
end

function conversation_reference(activity::AbstractDict)
    service_url = get(() -> nothing, activity, "serviceUrl")
    conversation = get(() -> nothing, activity, "conversation")
    user = get(() -> nothing, activity, "from")
    bot = get(() -> nothing, activity, "recipient")
    channel_id = get(() -> nothing, activity, "channelId")
    service_url === nothing && throw(MSTeamsRequestError("Activity missing serviceUrl"))
    conversation === nothing && throw(MSTeamsRequestError("Activity missing conversation"))
    user === nothing && throw(MSTeamsRequestError("Activity missing from"))
    bot === nothing && throw(MSTeamsRequestError("Activity missing recipient"))
    return JSON.Object(
        "serviceUrl" => String(service_url),
        "conversation" => conversation,
        "user" => user,
        "bot" => bot,
        "channelId" => channel_id,
    )
end

function send_proactive(client::BotClient, reference::AbstractDict; text::AbstractString, entities=nothing, attachments=nothing, channel_data=nothing)
    service_url = get(() -> nothing, reference, "serviceUrl")
    conversation = get(() -> nothing, reference, "conversation")
    user = get(() -> nothing, reference, "user")
    bot = get(() -> nothing, reference, "bot")
    channel_id = get(() -> nothing, reference, "channelId")
    service_url === nothing && throw(MSTeamsRequestError("Reference missing serviceUrl"))
    conversation === nothing && throw(MSTeamsRequestError("Reference missing conversation"))
    user === nothing && throw(MSTeamsRequestError("Reference missing user"))
    bot === nothing && throw(MSTeamsRequestError("Reference missing bot"))
    conversation_id = get(() -> nothing, conversation, "id")
    conversation_id === nothing && throw(MSTeamsRequestError("Reference conversation missing id"))
    return send_message(
        client;
        service_url=String(service_url),
        conversation_id=String(conversation_id),
        text=text,
        from=bot,
        recipient=user,
        channel_id=channel_id,
        entities=entities,
        attachments=attachments,
        channel_data=channel_data,
    )
end

function mentions(activity::AbstractDict)
    entities = get(() -> nothing, activity, "entities")
    entities === nothing && return []
    matches = []
    for entity in entities
        entity_type = get(() -> nothing, entity, "type")
        entity_type == "mention" && push!(matches, entity)
    end
    return matches
end

function bot_is_mentioned(activity::AbstractDict)
    recipient = get(() -> nothing, activity, "recipient")
    recipient === nothing && return false
    bot_id = get(() -> nothing, recipient, "id")
    bot_id === nothing && return false
    for entity in mentions(activity)
        mentioned = get(() -> nothing, entity, "mentioned")
        mentioned === nothing && continue
        mentioned_id = get(() -> nothing, mentioned, "id")
        mentioned_id === nothing && continue
        lowercase(String(mentioned_id)) == lowercase(String(bot_id)) && return true
    end
    return false
end
