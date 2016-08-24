[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = credentials?eval]
[#assign configurationObject = configuration?eval]
[#assign stackOutputsObject = stackOutputs?eval]

[#-- High level objects --]
[#assign tenantObject = blueprintObject.Tenant]
[#assign accountObject = blueprintObject.Account]

[#-- Reference data --]
[#assign regions = blueprintObject.Regions]
[#assign categories = blueprintObject.Categories]

[#-- Reference Objects --]
[#assign regionObject = regions[accountRegion]]
[#assign categoryObject = categories["alm"]]

[#-- Key ids/names --]
[#assign tenantId = tenantObject.Id]
[#assign accountId = accountObject.Id]
[#assign accountName = accountObject.Name]
[#assign regionId = regionObject.Id]
[#assign categoryId = categoryObject.Id]

[#-- Domains --]
[#assign accountDomainStem = (accountObject.Domain.Stem)!"gosource.com.au"]
[#assign accountDomainBehaviour = (accountObject.Domain.AccountBehaviour)!""]
[#switch accountDomainBehaviour]
    [#case "naked"]
        [#assign accountDomain = accountDomainStem]
        [#break]
    [#case "includeAccountId"]
       [#default]
       [#assign accountDomain = accountId + "." + accountDomainStem]
[/#switch]

{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : {
        [#-- Standard S3 buckets --]
        [#assign buckets = ["credentials", "code"]]
        [#list buckets as bucket]
            "s3X${bucket}" : {
                "Type" : "AWS::S3::Bucket",
                "Properties" : {
                    "BucketName" : "${bucket}.${accountDomain}",
                    "Tags" : [ 
                        { "Key" : "cot:product", "Value" : "${accountId}" },
                        { "Key" : "cot:category", "Value" : "${categoryId}" }
                    ]
                }
            }
            [#if !(bucket == buckets?last)],[/#if]
        [/#list]
    },
    "Outputs" : {
        "domainXaccountXdomain" : {
            "Value" : "${accountDomain}"
        }
        [#list buckets as bucket]
            ,"s3XaccountX${bucket}" : {
                "Value" : { "Ref" : "s3X${bucket}" }
            }
        [/#list]
    }
}


