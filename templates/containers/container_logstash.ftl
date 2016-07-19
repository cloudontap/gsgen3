[#case "logstash"]
    [#switch containerListMode]
        [#case "definition"]
            "Name" : "${tier.Name + "-" + component.Name + "-" + container.Id}",
            "Image" : "${docker.Registry}/logstash${dockerTag}",
            "Environment" : [
                [@standardEnvironmentVariables /]
                {
                    "Name" : "LOGS",
                    "Value" : "${logsBucket}"
                },
                {
                    "Name" : "REGION",
                    "Value" : "${regionId}"
                },
                {
                    "Name" : "PROJECT",
                    "Value" : "${projectId}"
                },
                {
                    "Name" : "CONTAINER",
                    "Value" : "${containerId}"
                },
                [#assign esConfiguration = configurationObject.ElasticSearch]
                {
                    "Name" : "ES",
                    "Value" : "${esConfiguration.EndPoint}"
                },
                [#if esConfiguration.MaximumIndexAge??]
                    {
                        "Name" : "INDEX_AGE",
                        "Value" : "${esConfiguration.MaximumIndexAge}"
                    }
                [/#if]
            ],
            "MountPoints": [
                {
                    "SourceVolume": "logstash",
                    "ContainerPath": "/project/logstash",
                    "ReadOnly": false
                }
            ],
            "Essential" : true,
            [#break]

        [#case "volumeCount"]
            [#assign volumeCount = volumeCount + 1]
            [#break]

        [#case "volumes"]
            [#if volumeCount > 0],[/#if]
            {
                "Host": {
                    "SourcePath": "/project/logstash"
                },
                "Name": "logstash"
            }
            [#assign volumeCount = volumeCount + 1]
            [#break]

        [#case "supplemental"]
            ,"policyX${tier.Id}X${component.Id}Xs3" : {
                "Type": "AWS::IAM::Policy",
                "Properties": {
                    "PolicyDocument" : {
                        "Version": "2012-10-17",
                        "Statement": [
                            {
                                "Resource": [
                                    "arn:aws:s3:::${logsBucket}/*"
                                ],
                                "Action": [
                                   "s3:GetObject",
                                   "s3:DeleteObject"
                                ],
                                "Effect": "Allow"
                            }
                        ]
                    },
                    "PolicyName": "${tier.Id}-${component.Id}-s3",
                    "Roles" : [ "${getKey("roleX" + tier.Id + "X" + component.Id)}"]
                }
            }
            [#break]

    [/#switch]
    [#break]
