export release_session_key
export disconnect!

function release_session_key(client::LimeSurveyClient)
    payload = construct_payload("release_session_key", [client.session_key])
    response = call_limesurvey_api(client, payload)
    return response
end

function disconnect!(client::LimeSurveyClient)
    release_session_key(client)
    client.session_key = nothing
    @info "Disconnected from server '$(client.url)'"
    return nothing
end
