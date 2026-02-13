module MSTeams

using Dates
using HTTP
using JSON
using Logging
using ZipFile

const SDK_VERSION = v"0.1.0"

include("errors.jl")
include("utils.jl")
include("client.jl")
include("server.jl")
include("manifest.jl")

export SDK_VERSION
export BotClient, BotToken
export start_server, run_server
export reply_text, reply_activity, send_message, send_activity, send_proactive
export conversation_reference, mentions, bot_is_mentioned
export build_manifest, write_manifest_bundle
export MSTeamsError, MSTeamsRequestError, MSTeamsAuthError, MSTeamsResponseError, MSTeamsConfigurationError

end # module MSTeams
