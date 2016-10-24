[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = credentials?eval]
[#assign appSettingsObject = appsettings?eval]
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
[#assign accountDomainStem = accountObject.Domain.Stem]
[#assign accountDomainBehaviour = (accountObject.Domain.AccountBehaviour)!""]
[#assign accountDomainCertificateId = accountObject.Domain.Certificate.Id]
[#switch accountDomainBehaviour]
    [#case "accountInDomain"]
        [#assign accountDomain = accountName + "." + accountDomainStem]
        [#assign accountDomainQualifier = ""]
        [#assign accountDomainCertificateId = accountDomainCertificateId + "-" + accountId]
        [#break]
    [#case "naked"]
        [#assign accountDomain = accountDomainStem]
        [#assign accountDomainQualifier = ""]
        [#break]
    [#case "accountInHost"]
    [#default]
        [#assign accountDomain = accountDomainStem]
        [#assign accountDomainQualifier = "-" + accountName]
        [#break]
[/#switch]

[#assign buckets = ["credentials", "code"]]


{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : {
        [#assign sliceCount = 0]
        [#if slice?contains("s3")]
            [#-- Standard S3 buckets --]
            [#if sliceCount > 0],[/#if]
            [#list buckets as bucket]
                "s3X${bucket}" : {
                    "Type" : "AWS::S3::Bucket",
                    "Properties" : {
                        "BucketName" : "${bucket}${accountDomainQualifier}.${accountDomain}",
                        "Tags" : [ 
                            { "Key" : "cot:request", "Value" : "${request}" },
                            { "Key" : "cot:account", "Value" : "${accountId}" },
                            { "Key" : "cot:category", "Value" : "${categoryId}" }
                        ]
                    }
                }
                [#if !(bucket == buckets?last)],[/#if]
            [/#list]
            [#assign sliceCount = sliceCount + 1]
        [/#if]
        
        [#if slice?contains("cert")]
            [#-- Generate certificate --]
            [#if sliceCount > 0],[/#if]
            "certificate" : {
                "Type" : "AWS::CertificateManager::Certificate",
                "Properties" : {
                    "DomainName" : "*.${accountDomain}",
                    "DomainValidationOptions" : [
                        {
                            "DomainName" : "*.${accountDomain}",
                            "ValidationDomain" : "${tenantObject.Domain.Validation}"
                        }
                    ]
                }
            }
            [#assign sliceCount = sliceCount + 1]
        [/#if]        
    },
    "Outputs" : {
        [#assign sliceCount = 0]
        [#if slice?contains("s3")]
            [#if sliceCount > 0],[/#if]
            "domainXaccountXdomain" : {
                "Value" : "${accountDomain}"
            },
            "domainXaccountXqualifier" : {
                "Value" : "${accountDomainQualifier}"
            },
            [#list buckets as bucket]
                "s3XaccountX${bucket}" : {
                    "Value" : { "Ref" : "s3X${bucket}" }
                }
                [#if !(bucket == buckets?last)],[/#if]
            [/#list]
            [#assign sliceCount = sliceCount + 1]
        [/#if]
        
        [#if slice?contains("cert")]
            [#if sliceCount > 0],[/#if]
            "certificateX${accountDomainCertificateId}" : {
                "Value" : { "Ref" : "certificate" }
            }
            [#assign sliceCount = sliceCount + 1]
        [/#if]
        
    }
}


