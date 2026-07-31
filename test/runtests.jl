using HTTP
using JSON
using MSTeams
using Test

server_port(server) = Int(HTTP.port(server))

@testset "HTTP 2 request and response bodies" begin
    received = Channel{Any}(1)
    handler = MSTeams.build_server_handler() do activity
        put!(received, activity)
        return nothing
    end
    inbound = HTTP.serve!(handler, "127.0.0.1", 0)
    try
        url = "http://127.0.0.1:$(server_port(inbound))/api/messages"
        response = HTTP.post(
            url,
            ["Content-Type" => "application/json"],
            JSON.json(Dict("type" => "message", "text" => "hello")),
        )
        @test response.status == 200
        activity = fetch(@async take!(received))
        @test activity["type"] == "message"
        @test activity["text"] == "hello"
    finally
        close(inbound)
    end

    seen_authorization = Ref("")
    outbound = HTTP.serve!("127.0.0.1", 0) do req
        path = String(HTTP.URI(req.target).path)
        if path == "/token"
            return HTTP.Response(
                200,
                ["Content-Type" => "application/json"],
                JSON.json(Dict("access_token" => "test-token", "expires_in" => 3600)),
            )
        end
        seen_authorization[] = HTTP.header(req, "Authorization", "")
        return HTTP.Response(
            200,
            ["Content-Type" => "application/json"],
            JSON.json(Dict("id" => "activity-1")),
        )
    end
    try
        base = "http://127.0.0.1:$(server_port(outbound))"
        client = MSTeams.BotClient(;
            app_id = "app",
            app_password = "secret",
            token_url = "$base/token",
        )
        result = MSTeams.send_activity(
            client,
            base,
            "conversation",
            Dict("type" => "message", "text" => "hello"),
        )
        @test result["id"] == "activity-1"
        @test seen_authorization[] == "Bearer test-token"
    finally
        close(outbound)
    end
end
