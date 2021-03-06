export list_survey_groups

function list_survey_groups(client::LimeSurveyClient, username::Union{Nothing,String}=nothing)
    payload = construct_payload("list_survey_groups", [client.session_key, username])
    response = call_limesurvey_api(client, payload)
    return response
end
