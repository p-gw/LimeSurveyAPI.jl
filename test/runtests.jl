using LimeSurveyAPI
using Test

using Base64
using CSV
using DataFrames
using JSON3

function dataframe_to_base64csv(df::DataFrame)
    io = IOBuffer()
    CSV.write(io, df)
    df_encoded = io.data[io.data.!=0x00] |> String |> base64encode
    return df_encoded
end

@testset "LimeSurveyAPI.jl" begin
    @testset "utils.jl" begin
        @test LimeSurveyAPI.filename("test.csv") == "test.csv"
        @test LimeSurveyAPI.filename("./test.csv") == "test.csv"
        @test LimeSurveyAPI.filename("C:/Program Files/test.csv") == "test.csv"

        @test LimeSurveyAPI.fileextension("test.csv") == "csv"
        @test LimeSurveyAPI.fileextension("test.1.csv") == "csv"
        @test LimeSurveyAPI.fileextension("test_1.csv") == "csv"
        @test LimeSurveyAPI.fileextension("./test.csv") == "csv"
        @test LimeSurveyAPI.fileextension("./test.1.csv") == "csv"
        @test LimeSurveyAPI.fileextension("C:/Program Files/test.csv") == "csv"

        encoded = base64encode("Teststring")
        @test LimeSurveyAPI.base64_to_string(encoded) == "Teststring"

        df = DataFrame(a=1:3, b=["a", "b", "c"])
        df_encoded = dataframe_to_base64csv(df)
        @test LimeSurveyAPI.base64csv_to_sink(df_encoded, DataFrame) == df
    end

    @testset "Client" begin
        url = "https://www.test.co"
        c = LimeSurveyClient(url)
        @test c.url == url
        @test isnothing(c.session_key)
    end

    @testset "payloads" begin
        headers = LimeSurveyAPI.construct_headers()
        @test headers isa Dict
        @test headers["Content-type"] == "application/json"

        payload = LimeSurveyAPI.construct_payload("test_method", [1, "a", []])
        @test payload isa String

        payload_obj = JSON3.read(payload)
        @test payload_obj.method == "test_method"
        @test payload_obj.id isa String
        @test payload_obj.params == [1, "a", []]
    end

    @testset "Integration tests" begin
        c = LimeSurveyClient("http://127.0.0.1:8082/index.php/admin/remotecontrol")
        connect!(c, "admin", "password")

        initial_surveys = list_surveys(c)
        @test initial_surveys.result[:status] == "No surveys found"

        # add surveys
        s1 = add_survey!(c, 123456, "testsurvey-1", "en")
        s2 = add_survey!(c, 111111, "testsurvey-2", "en")
        s3 = add_survey!(c, 222222, "testsurvey-3", "en")

        @test s1.result == 123456
        @test s2.result == 111111
        @test s3.result == 222222

        s4 = add_survey!(c, 999999, "testsurvey-4", "invalid language")
        @test s4.result[:status] == "Faulty parameters"

        # duplicate ids result in random survey id
        s5 = add_survey!(c, 123456, "testsurvey-5", "en")
        @test s5 != 123456

        # list surveys (basic)
        survey_list = list_surveys(c)
        @test length(survey_list.result) == 4

        # list surveys (DataFrame sink)
        survey_list = list_surveys(c, DataFrame)
        @test survey_list isa DataFrame
        @test nrow(survey_list) == 4
        @test names(survey_list) == ["sid", "surveyls_title", "startdate", "expires", "active"]

        # add question groups
        g1 = add_group!(c, s1.result, "first group")
        g2 = add_group!(c, s1.result, "second group", description="description")

        @test g1.result == 1
        @test g2.result == 2

        # list groups (basic)
        gl1 = list_groups(c, s1.result)
        @test length(gl1.result) == 2
        @test gl1.result[1][:group_name] == "first group"
        @test gl1.result[2][:group_name] == "second group"
        @test gl1.result[1][:description] == ""
        @test gl1.result[2][:description] == "description"

        gl2 = list_groups(c, s2.result)
        @test gl2.result[:status] == "No groups found"

        # list groups (DataFrame sink)
        gl1 = list_groups(c, s1.result, DataFrame)
        @test nrow(gl1) == 2
        @test gl1[1, :group_name] == "first group"
        @test gl1[2, :group_name] == "second group"
        @test gl1[1, :description] == ""
        @test gl1[2, :description] == "description"

        # import surveys
        s6 = import_survey!(c, "limesurvey/813998.lss")
        @test s6.result == 813998
        s6_groups = list_groups(c, s6.result)
        @test length(s6_groups.result) == 2
        @test s6_groups.result[1].group_name == "test group"
        @test s6_groups.result[1].description == "some description"
        @test s6_groups.result[2].group_name == "test group 2"
        @test s6_groups.result[2].description == "."

        # list questions
        qs = list_questions(c, s6.result)
        @test length(qs.result) == 2
        @test qs.result[1].question == "Make a long statement!"
        @test qs.result[1].help == "need help?"
        @test qs.result[2].question == "Rate on a scale from 1 to 5!"
        @test qs.result[2].help == "need help?"

        gid = parse(Int, last(s6_groups.result).gid)
        qg2 = list_questions(c, s6.result, gid)
        @test length(qg2.result) == 1
        @test qg2.result[1].question == qs.result[2].question

        # activate surveys
        res = activate_survey!(c, 100000)
        @test res.result[:status] == "Error: Invalid survey ID"
        @test_throws ErrorException is_active(c, 100000)

        res = activate_survey!(c, s1.result)
        @test res.result[:status] == "Error: Survey does not pass consistency check"
        @test is_active(c, s1.result) == false

        res = activate_survey!(c, s6.result)  # s6 contains questions and should be ready to activate
        @test res.result[:status] == "OK"
        @test is_active(c, s6.result) == true
    end
end
