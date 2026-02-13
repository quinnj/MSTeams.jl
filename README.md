# MSTeams.jl

Lightweight Microsoft Teams bot client + webhook server for receiving activities and replying via the Bot Framework connector API.

## Quick start

```julia
using MSTeams

client = BotClient(
    app_id=ENV["MSTEAMS_APP_ID"],
    app_password=ENV["MSTEAMS_APP_PASSWORD"],
)

handler = function(activity)
    activity_type = get(() -> nothing, activity, "type")
    activity_type != "message" && return
    text = get(() -> "", activity, "text")
    return "Echo: $(text)"
end

server = start_server(handler; client=client, host="0.0.0.0", port=3978, path="/api/messages")
```

The handler can return:
- `nothing` to ignore
- `String` to reply with text
- `Dict`/`JSON.Object` for a full activity payload

## Proactive messaging

Store a conversation reference from an incoming activity, then use it later:

```julia
using MSTeams

references = Dict{String, Any}()

handler = function(activity)
    user = get(() -> JSON.Object(), activity, "from")
    user_id = get(() -> "unknown", user, "id")
    references[user_id] = conversation_reference(activity)
    return "Stored conversation reference."
end

# Later on:
ref = references["some-user-id"]
send_proactive(client, ref; text="Hello from a scheduled job")
```

## Manifest bundle generator

Create a sideloadable Teams app package (zip) containing `manifest.json` and icons:

```julia
using MSTeams

bundle = write_manifest_bundle(
    "build/teams-app";
    app_id="YOUR-TEAMS-APP-ID",
    bot_id="YOUR-BOT-REGISTRATION-ID",
    name_short="My Teams Bot",
    description_short="Responds to mentions",
    developer_name="Your Name",
    developer_website="https://example.com",
    developer_privacy="https://example.com/privacy",
    developer_terms="https://example.com/terms",
)

println(bundle.bundle)
```

To use custom icons:

```julia
write_manifest_bundle(
    "build/teams-app";
    app_id="YOUR-TEAMS-APP-ID",
    bot_id="YOUR-BOT-REGISTRATION-ID",
    name_short="My Teams Bot",
    description_short="Responds to mentions",
    developer_name="Your Name",
    color_icon_path="assets/color.png",
    outline_icon_path="assets/outline.png",
)
```

## Notes

- Incoming activity validation (Bot Framework JWT verification) is not implemented yet.
- Teams will deliver POSTs to a single messaging endpoint; ensure your server is reachable via HTTPS for production use.
