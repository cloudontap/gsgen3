[#case "filter"]
    [#switch containerListMode]
        [#case "definition"]
            [#assign filterContainer = tier.Name + "-" + component.Name + "-" + container.Id]
            "Name" : "${filterContainer}",
            "Image" : "${docker.Registry}/esfilter${dockerTag}",
            "Environment" : [
                [@standardEnvironmentVariables /]
                {
                    "Name" : "CONFIGURATION",
                    "Value" : "${configuration?json_string}"
                },
                {
                    "Name" : "ES",
                    "Value" : "${getKey("esXanaX" + component.Id + "Xdns") + ":443"}"
                },
                [#assign sharedCredential = credentialsObject["shared"]]
                {
                    "Name" : "DATA_USERNAME",
                    "Value" : "${sharedCredential.Data.Username}"
                },
                {
                    "Name" : "DATA_PASSWORD",
                    "Value" : "${sharedCredential.Data.Password}"
                },
                {
                    "Name" : "QUERY_USERNAME",
                    "Value" : "${sharedCredential.Query.Username}"
                },
                {
                    "Name" : "QUERY_PASSWORD",
                    "Value" : "${sharedCredential.Query.Password}"
                }
            ],
            "Essential" : true,
            [#break]

    [/#switch]
    [#break]

