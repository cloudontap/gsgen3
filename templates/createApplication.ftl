[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = (credentials?eval).Credentials]
[#assign appSettingsObject = appsettings?eval]
[#assign stackOutputsObject = stackOutputs?eval]

[#-- High level objects --]
[#assign tenantObject = blueprintObject.Tenant]
[#assign accountObject = blueprintObject.Account]
[#assign productObject = blueprintObject.Product]
[#assign solutionObject = blueprintObject.Solution]
[#assign solutionTiers = solutionObject.Tiers]
[#assign segmentObject = blueprintObject.Segment]

[#-- Reference data --]
[#assign regions = blueprintObject.Regions]
[#assign environments = blueprintObject.Environments]
[#assign categories = blueprintObject.Categories]
[#assign tiers = blueprintObject.Tiers]
[#assign routeTables = blueprintObject.RouteTables]
[#assign networkACLs = blueprintObject.NetworkACLs]
[#assign storage = blueprintObject.Storage]
[#assign processors = blueprintObject.Processors]
[#assign ports = blueprintObject.Ports]
[#assign portMappings = blueprintObject.PortMappings]

[#-- Reference Objects --]
[#assign regionObject = regions[region]]
[#assign accountRegionObject = regions[accountRegion]]
[#assign productRegionObject = regions[productRegion]]
[#assign environmentObject = environments[segmentObject.Environment]]
[#assign categoryObject = categories[segmentObject.Category!environmentObject.Category]]

[#-- Key ids/names --]
[#assign tenantId = tenantObject.Id]
[#assign accountId = accountObject.Id]
[#assign productId = productObject.Id]
[#assign productName = productObject.Name]
[#assign segmentId = segmentObject.Id!environmentObject.Id]
[#assign segmentName = segmentObject.Name!environmentObject.Name]
[#assign regionId = regionObject.Id]
[#assign accountRegionId = accountRegionObject.Id]
[#assign productRegionId = productRegionObject.Id]
[#assign environmentId = environmentObject.Id]
[#assign environmentName = environmentObject.Name]
[#assign categoryId = categoryObject.Id]

[#-- Domains --]
[#assign segmentDomain = getKey("domainXsegmentXdomain")]
[#assign segmentDomainQualifier = getKey("domainXsegmentXqualifier")]

[#-- Buckets --]
[#assign credentialsBucket = getKey("s3XaccountXcredentials")!"unknown"]
[#assign codeBucket = getKey("s3XaccountXcode")!"unknown"]
[#assign logsBucket = getKey("s3XsegmentXlogs")]
[#assign backupsBucket = getKey("s3XsegmentXbackups")]

[#-- AZ List --]
[#assign azList = segmentObject.AZList]

[#-- Loop optimisation --]
[#assign lastTier = solutionTiers?last]
[#assign firstZone = azList?first]
[#assign lastZone = azList?last]
[#assign zoneCount = azList?size]

[#-- Get stack output --]
[#function getKey key]
    [#list stackOutputsObject as pair]
        [#if pair.OutputKey==key]
            [#return pair.OutputValue]
        [/#if]
    [/#list]
[/#function]

[#-- Locate the object for a tier --]
[#function getTier tier]
    [#return tiers[tier]]
[/#function]

[#-- Locate the object for a component within tier --]
[#function getComponent tier component]
    [#list solutionTiers as t]
        [#if t.Id == tier]
            [#list t.Components as c]
                [#if c.Id == component]
                    [#return c]
                [/#if]
            [/#list]
        [/#if]
    [/#list]
[/#function]

[#-- Application --]
[#assign docker = appSettingsObject.Docker]
[#assign solnMultiAZ = solutionObject.MultiAZ!environmentObject.MultiAZ!false]
[#assign vpc = getKey("vpcXsegmentXvpc")]

[#if buildReference??]
    [#assign buildCommit = buildReference]
    [#assign buildSeparator = buildReference?index_of(" ")]
    [#if buildSeparator != -1]
        [#assign buildCommit = buildReference[0..(buildSeparator-1)]]
        [#assign appReference = buildReference[(buildSeparator+1)..]]
    [/#if]
[/#if]

[#macro standardEnvironmentVariables]
    {
        "Name" : "TEMPLATE_TIMESTAMP",
        "Value" : "${.now?iso_utc}"
    },
    {
        "Name" : "ENVIRONMENT",
        "Value" : "${environmentName}"
    }
    [#if configurationReference??]
        ,{
            "Name" : "CONFIGURATION_REFERENCE",
            "Value" : "${configurationReference}"
        }
    [/#if]
    [#if buildCommit??]
        ,{
            "Name" : "BUILD_REFERENCE",
            "Value" : "${buildCommit}"
        }
    [/#if]
    [#if appReference?? && (appReference != "")]
        ,{
            "Name" : "APP_REFERENCE",
            "Value" : "${appReference}"
        }
    [/#if]
[/#macro]

[#macro createTask tier component task]
    "ecsTaskX${tier.Id}X${component.Id}X${task.Id}" : {
        "Type" : "AWS::ECS::TaskDefinition",
        "Properties" : {
            "ContainerDefinitions" : [
                [#list task.Containers as container]
                    [#assign dockerTag = ""]
                    [#if container.Version??]
                        [#assign dockerTag = ":" + container.Version]
                    [/#if]
                    {
                        [#assign containerListMode = "definition"]
                        [#include containerList]
                        "Memory" : "${container.Memory?c}",
                        "Cpu" : "${container.Cpu?c}",
                        [#if container.Ports??]
                            "PortMappings" : [
                                [#list container.Ports as port]
                                    {
                                        [#if port.Container??]
                                            "ContainerPort" : ${ports[port.Container].Port?c},
                                        [#else]
                                            "ContainerPort" : ${ports[port.Id].Port?c},
                                        [/#if]
                                        [#if port.DynamicHostPort?? && port.DynamicHostPort]
                                            "HostPort" : 0
                                        [#else]
                                            "HostPort" : ${ports[port.Id].Port?c}
                                        [/#if]
                                    }[#if !(port.Id == (container.Ports?last).Id)],[/#if]
                                [/#list]
                            ],
                        [/#if]
                        "LogConfiguration" : {
                            [#if (docker.LocalLogging?? && (docker.LocalLogging == true)) || (container.LocalLogging?? && (container.LocalLogging == true))]
                                "LogDriver" : "json-file"
                            [#else]
                                "LogDriver" : "fluentd",
                                "Options" : { "tag" : "docker.${productId}.${segmentId}.${tier.Id}.${component.Id}.${container.Id}"}
                            [/#if]
                        }
                    }[#if container.Id != (task.Containers?last).Id],[/#if]
                [/#list]
            ]
            [#assign volumeCount = 0]
            [#list task.Containers as container]
                [#assign containerListMode = "volumeCount"]
                [#include containerList]
            [/#list]
            [#if volumeCount > 0]
                ,"Volumes" : [
                    [#assign volumeCount = 0]
                    [#list task.Containers as container]
                        [#assign containerListMode = "volumes"]
                        [#include containerList]
                    [/#list]
                ]
            [/#if]
        }
    }
[/#macro]

[#macro createTargetGroup tier component source destination name]
    "tgX${tier.Id}X${component.Id}X${source.Port?c}X${name}" : {
        "Type" : "AWS::ElasticLoadBalancingV2::TargetGroup",
        "Properties" : {
            "HealthCheckPort" : "${(destination.HealthCheck.Port)!destination.Port?c}",
            "HealthCheckProtocol" : "${(destination.HealthCheck.Protocol)!destination.Protocol}",
            "HealthCheckPath" : "${destination.HealthCheck.Path}",
            "HealthCheckIntervalSeconds" : ${destination.HealthCheck.Interval},
            "HealthCheckTimeoutSeconds" : ${destination.HealthCheck.Timeout},
            "HealthyThresholdCount" : ${destination.HealthCheck.HealthyThreshold},
            "UnhealthyThresholdCount" : ${destination.HealthCheck.UnhealthyThreshold},
            [#if (destination.HealthCheck.SuccessCodes)?? ]
                "Matcher" : { "HttpCode" : "${destination.HealthCheck.SuccessCodes}" },
            [/#if]
            "Port" : ${destination.Port?c},
            "Protocol" : "${destination.Protocol}",
            "Tags" : [
                { "Key" : "cot:request", "Value" : "${request}" },
                { "Key" : "cot:account", "Value" : "${accountId}" },
                { "Key" : "cot:product", "Value" : "${productId}" },
                { "Key" : "cot:segment", "Value" : "${segmentId}" },
                { "Key" : "cot:environment", "Value" : "${environmentId}" },
                { "Key" : "cot:category", "Value" : "${categoryId}" },
                { "Key" : "cot:tier", "Value" : "${tier.Id}" },
                { "Key" : "cot:component", "Value" : "${component.Id}" },
                { "Key" : "Name", "Value" : "${productName}-${segmentName}-${tier.Name}-${component.Name}-${source.Port?c}-${name}" }
            ],
            "VpcId": "${vpc}"
        }
    }
[/#macro]

{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : 
    {
        [#assign count = 0]
        [#list solutionTiers as solutionTier]
            [#assign tier = tiers[solutionTier.Id]]
            [#if solutionTier.Components??]
                [#list solutionTier.Components as component]
                    [#assign slices = component.Slices!solutionTier.Slices!tier.Slices]
                    [#if slices?seq_contains(slice)]
                        [#if component.MultiAZ??] 
                            [#assign multiAZ =  component.MultiAZ]
                        [#else]
                            [#assign multiAZ =  solnMultiAZ]
                        [/#if]
                        [#-- ECS --]
                        [#if component.ECS??]
                            [#assign ecs = component.ECS]
                            [#assign fixedIP = ecs.FixedIP?? && ecs.FixedIP]
                            [#assign ecsSG = getKey("securityGroupX" + tier.Id + "X" + component.Id) ]
                            [#if ecs.Services??]
                                [#list ecs.Services as service]
                                    [#assign serviceSlices = service.Slices!component.Slices!solutionTier.Slices!tier.Slices]
                                    [#if serviceSlices?seq_contains(slice)]
                                        [#if count > 0],[/#if]
                                        [@createTask tier=tier component=component task=service /],
                                        "ecsServiceX${tier.Id}X${component.Id}X${service.Id}" : {
                                            "Type" : "AWS::ECS::Service",
                                            "Properties" : {
                                                "Cluster" : "${getKey("ecsX" + tier.Id + "X" + component.Id)}",
                                                "DeploymentConfiguration" : {
                                                    [#if multiAZ]
                                                        "MaximumPercent" : 100,
                                                        "MinimumHealthyPercent" : 50
                                                    [#else]
                                                        "MaximumPercent" : 100,
                                                        "MinimumHealthyPercent" : 0
                                                    [/#if]
                                                },
                                                [#if service.DesiredCount??]
                                                    "DesiredCount" : "${service.DesiredCount}",
                                                [#else]
                                                    "DesiredCount" : "${multiAZ?string(zoneCount,"1")}",
                                                [/#if]
                                                [#assign portCount = 0]
                                                [#list service.Containers as container]
                                                    [#if container.Ports??]
                                                        [#list container.Ports as port]
                                                            [#if port.ELB?? || port.LB??]
                                                                [#assign portCount = portCount + 1]
                                                                [#break]
                                                            [/#if]
                                                        [/#list]
                                                    [/#if]
                                                [/#list]
                                                [#if portCount != 0]
                                                    "LoadBalancers" : [
                                                        [#assign portCount = 0]
                                                        [#list service.Containers as container]
                                                            [#if container.Ports??]
                                                                [#list container.Ports as port]
                                                                    [#if port.ELB?? || port.LB??]
                                                                        [#if portCount > 0],[/#if]
                                                                        {
                                                                            [#if port.LB??]
                                                                                [#assign lb = port.LB]
                                                                                 [#if lb.Port??]
                                                                                    [#assign lbPort = lb.Port]
                                                                                [#else] 
                                                                                    [#assign lbPort = port.Id]
                                                                                [/#if]
                                                                                [#if lb.TargetGroup??]
                                                                                    [#assign targetGroupKey = "tgX" + lb.Tier + "X" + lb.Component + "X" + ports[lbPort].Port?c + "X" + lb.TargetGroup]
                                                                                    [#if getKey(targetGroupKey)??]
                                                                                        "TargetGroupArn" : "${getKey(targetGroupKey)}",
                                                                                    [#else]
                                                                                        "TargetGroupArn" : { "ref" : "${targetGroupKey}" },
                                                                                    [/#if]
                                                                                [#else]
                                                                                    "LoadBalancerName" : "${getKey("elbX" + port.lb.Tier + "X" + port.lb.Component)}",
                                                                                [/#if]
                                                                            [#else]
                                                                                "LoadBalancerName" : "${getKey("elbXelbX" + port.ELB)}",
                                                                            [/#if]
                                                                            "ContainerName" : "${tier.Name + "-" + component.Name + "-" + container.Id}",
                                                                            [#if port.Container??]
                                                                                "ContainerPort" : ${ports[port.Container].Port?c}
                                                                            [#else]
                                                                                "ContainerPort" : ${ports[port.Id].Port?c}
                                                                            [/#if]
                                                                        }
                                                                        [#assign portCount = portCount + 1]
                                                                    [/#if]
                                                                [/#list]
                                                            [/#if]
                                                        [/#list]
                                                    ],
                                                    "Role" : "${getKey("roleX" + tier.Id + "X" + component.Id + "Xservice")}",
                                                [/#if]
                                                "TaskDefinition" : { "Ref" : "ecsTaskX${tier.Id}X${component.Id}X${service.Id}" }
                                            }
                                        }
                                        [#list service.Containers as container]
                                            [#-- Supplemental definitions for the container --] 
                                            [#assign containerListMode = "supplemental"]
                                            [#include containerList]

                                            [#-- Security Group ingress for the container ports --] 
                                            [#if container.Ports??]
                                                [#list container.Ports as port]
                                                    [#assign useDynamicHostPort = port.DynamicHostPort?? && port.DynamicHostPort]
                                                    [#if useDynamicHostPort]
                                                        [#assign portRange = "dynamic"]
                                                    [#else]
                                                        [#assign portRange = ports[port.Id].Port?c]
                                                    [/#if]
                                                    
                                                    [#assign fromSG = (port.ELB?? || port.LB??) && 
                                                        (((port.LB.fromSGOnly)?? && port.LB.fromSGOnly) || fixedIP)]

                                                    [#if fromSG]
                                                        [#if port.ELB??]
                                                            [#assign elbSG = getKey("securityGroupXelbX" + port.ELB)]
                                                        [#else]
                                                            [#assign elbSG = getKey("securityGroupX" + port.lb.Tier + "X" + port.lb.Component)]
                                                        [/#if]
                                                    [/#if]
                                                    ,"securityGroupIngressX${tier.Id}X${component.Id}X${service.Id}X${container.Id}X${portRange}" : {
                                                        "Type" : "AWS::EC2::SecurityGroupIngress",
                                                        "Properties" : {
                                                            "GroupId": "${ecsSG}",
                                                            "IpProtocol": "${ports[port.Id].IPProtocol}", 
                                                            [#if useDynamicHostPort]
                                                                "FromPort": "49153",
                                                                "ToPort": "65535",
                                                            [#else]
                                                                "FromPort": "${ports[port.Id].Port?c}", 
                                                                "ToPort": "${ports[port.Id].Port?c}", 
                                                            [/#if]
                                                            [#if fromSG]
                                                                "SourceSecurityGroupId": "${elbSG}"
                                                            [#else]
                                                                "CidrIp": "0.0.0.0/0"
                                                            [/#if]
                                                        }
                                                    }
                                                    [#if port.LB??]
                                                        [#assign lb = port.LB]
                                                        [#assign lbTier = getTier(lb.Tier)]
                                                        [#assign lbComponent = getComponent(lb.Tier, lb.Component)]
                                                        [#if lb.Port??]
                                                            [#assign lbPort = lb.Port]
                                                        [#else]
                                                            [#assign lbPort = port.Id]
                                                        [/#if]
                                                        [#if lb.TargetGroup??]
                                                            [#assign targetGroupKey = "tgX" + lbTier.Id + "X" + lbComponent.Id + "X" + ports[lbPort].Port?c + "X" + lb.TargetGroup]
                                                            [#if ! getKey(targetGroupKey)??]
                                                                ,[@createTargetGroup tier=lbTier component=lbComponent source=ports[lbPort] destination=ports[port.Id] name=lb.TargetGroup /]
                                                                ,"listenerRuleX${lbTier.Id}X${lbComponent.Id}X${ports[lbPort].Port?c}X${lb.TargetGroup})" : {
                                                                    "Type" : "AWS::ElasticLoadBalancingV2::ListenerRule",
                                                                    "Properties" : {
                                                                        [#if lb.Priority??]
                                                                            "Priority" : ${lb.Priority},
                                                                        [/#if]
                                                                        "Actions" : [
                                                                            {
                                                                                "Type": "forward",
                                                                                "TargetGroupArn": { "Ref": "${targetGroupKey}" }
                                                                            }
                                                                        ],
                                                                        "Conditions": [
                                                                            {
                                                                                "Field": "path-pattern",
                                                                                "Values": [ "${lb.Path}" ]
                                                                            }
                                                                        ],
                                                                        "ListenerArn" : "${getKey("listenerX" + lbTier.Id + "X" +  lbComponent.Id + "X" + ports[lbPort].Port?c)}"
                                                                    }
                                                                }
                                                            [/#if]
                                                        [/#if]
                                                    [/#if]
                                                [/#list]
                                            [/#if]
                                        [/#list]
                                        [#assign count = count + 1]
                                    [/#if]
                                [/#list]
                            [/#if]
                            [#if ecs.Tasks??]
                                [#list ecs.Tasks as task]
                                    [#assign taskSlices = task.Slices!component.Slices!solutionTier.Slices!tier.Slices]
                                    [#if taskSlices?seq_contains(slice)]
                                        [#if count > 0],[/#if]
                                        [@createTask tier=tier component=component task=task /]
                                        [#list task.Containers as container]
                                            [#assign containerListMode = "supplemental"]
                                            [#include containerList]
                                        [/#list]
                                        [#assign count = count + 1]
                                    [/#if]
                                [/#list]
                            [/#if]
                        [/#if]
                    [/#if]
                [/#list]
            [/#if]
        [/#list]
    },
    "Outputs" : 
    {
        [#assign count = 0]
        [#list solutionTiers as solutionTier]
            [#assign tier = tiers[solutionTier.Id]]
            [#if solutionTier.Components??]
                [#list solutionTier.Components as component]
                    [#assign slices = component.Slices!solutionTier.Slices!tier.Slices]
                    [#if slices?seq_contains(slice)]
                        [#-- ECS --]
                        [#if component.ECS??]
                            [#assign ecs = component.ECS]
                            [#if ecs.Services??]
                                [#list ecs.Services as service]
                                    [#assign serviceSlices = service.Slices!component.Slices!solutionTier.Slices!tier.Slices]
                                    [#if serviceSlices?seq_contains(slice)]
                                        [#if count > 0],[/#if]
                                            "ecsServiceX${tier.Id}X${component.Id}X${service.Id}" : {
                                                "Value" : { "Ref" : "ecsServiceX${tier.Id}X${component.Id}X${service.Id}" }
                                            },
                                            "ecsTaskX${tier.Id}X${component.Id}X${service.Id}" : {
                                                "Value" : { "Ref" : "ecsTaskX${tier.Id}X${component.Id}X${service.Id}" }
                                            }
                                            [#list service.Containers as container]
                                                [#if container.Ports??]
                                                    [#list container.Ports as port]
                                                        [#if port.LB??]
                                                            [#assign lb = port.LB]
                                                            [#if lb.Port??]
                                                                [#assign lbPort = lb.Port]
                                                            [#else] 
                                                                [#assign lbPort = port.Id]
                                                            [/#if]
                                                            [#if lb.TargetGroup??]
                                                                [#assign targetGroupKey = "tgX" + lb.Tier + "X" + lb.Component + "X" + ports[lbPort].Port?c + "X" + lb.TargetGroup]
                                                                [#if ! getKey(targetGroupKey)??]
                                                                    ,"${targetGroupKey}" : {
                                                                        "Value" : { "Ref" : "targetGroupKey" }
                                                                    }
                                                                [/#if]
                                                            [/#if]
                                                        [/#if]
                                                    [/#list]
                                                [/#if]
                                            [/#list]
                                            [#assign count = count + 1]
                                    [/#if]
                                [/#list]
                            [/#if]
                            [#if ecs.Tasks??]
                                [#list ecs.Tasks as task]
                                    [#assign taskSlices = task.Slices!component.Slices!solutionTier.Slices!tier.Slices]
                                    [#if taskSlices?seq_contains(slice)]
                                        [#if count > 0],[/#if]
                                            "ecsTaskX${tier.Id}X${component.Id}X${task.Id}" : {
                                                "Value" : { "Ref" : "ecsTaskX${tier.Id}X${component.Id}X${task.Id}" }
                                            }
                                            [#assign count = count + 1]
                                    [/#if]
                                [/#list]
                            [/#if]
                        [/#if]
                    [/#if]
                [/#list]
            [/#if]
        [/#list]
    }
}

