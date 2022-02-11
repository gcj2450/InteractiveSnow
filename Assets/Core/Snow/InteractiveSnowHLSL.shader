Shader "Custom/Snow Interactive"
{
    Properties
    {
        [Header(Main)]
        _Noise("Snow Noise", 2D) = "gray" {}
        _NoiseScale("Noise Scale", Range(0,2)) = 0.1
        _NoiseWeight("Noise Weight", Range(0,2)) = 0.1
        _Mask("Mask", 2D) = "white" {}// This mask prevents bleeding of the RT, make it white with a transparent edge around all sides, set to CLAMP, not repeat
        [Space]
        [Header(Tesselation)]
        _MaxTessDistance("Max Tessellation Distance", Range(10,100)) = 50
        _Tess("Tessellation", Range(1,32)) = 20
        [Space]
        [Header(Snow)]
        _Color("Snow Color", Color) = (0.5,0.5,0.5,1)
        _PathColor("Snow Path Color", Color) = (0.5,0.5,0.7,1)
        _MainTex("Snow Texture", 2D) = "white" {}
        _SnowHeight("Snow Height", Range(0,2)) = 0.3
        _SnowDepth("Snow Path Depth", Range(-2,2)) = 0.3
        _SnowTextureOpacity("Snow Texture Opacity", Range(0,2)) = 0.3
        _SnowTextureScale("Snow Texture Scale", Range(0,2)) = 0.3
        [Space]
        [Header(Sparkles)]
        _SparkleScale("Sparkle Scale", Range(0,10)) = 10
        _SparkCutoff("Sparkle Cutoff", Range(0,1)) = 0.1
        _SparklesIntensity("Sparkles Intensity", Range(0.5, 4)) = 1
        _SparkleNoise("Sparkle Noise", 2D) = "gray" {}
        [Space]
        [Header(NonSnow Textures)]
        _MainTexBase("Base Texture", 2D) = "white" {}
        _Scale("Base Scale", Range(0,2)) = 1
        _EdgeColor("Snow Edge Color", Color) = (0.5,0.5,0.5,1)
        _Edgewidth("Snow Edge Width", Range(0,0.2)) = 0.1
        [Space]
        [Header(Rim)]
        _RimPower("Rim Power", Range(0,20)) = 20
        _RimColor("Rim Color Snow", Color) = (0.5,0.5,0.5,1)
    }
    HLSLINCLUDE
    // Includes
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
    #include "SnowTessellation.hlsl"
    #pragma require tessellation tessHW
    #pragma vertex TessellationVertexProgram
    #pragma hull hull
    #pragma domain domain
    // Keywords
    #pragma multi_compile _ _SCREEN_SPACE_OCCLUSION
    #pragma multi_compile _ LIGHTMAP_ON
    #pragma multi_compile _ DIRLIGHTMAP_COMBINED
    #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
    #pragma multi_compile _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS _ADDITIONAL_OFF
    #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
    #pragma multi_compile _ _SHADOWS_SOFT
    #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
    #pragma multi_compile _ SHADOWS_SHADOWMASK


    ControlPoint TessellationVertexProgram(Attributes v)
    {
        ControlPoint p;
        p.vertex = v.vertex;
        p.uv = v.uv;
        p.normal = v.normal;
        p.color = v.color;
        return p;
    }
    ENDHLSL

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
            // vertex happens in snowtessellation.hlsl
            #pragma fragment frag

            sampler2D _MainTexBase, _MainTex, _SparkleNoise;
            float4 _Color, _RimColor;
            float _RimPower;
            float4 _EdgeColor;
            float _Edgewidth;
            float4 _PathColor;
            float _SparkleScale, _SparkCutoff, _SparklesIntensity;
            float _SnowTextureOpacity, _SnowTextureScale, _Scale;

            half4 frag(Varyings IN) : SV_Target
            {
                // Effects RenderTexture Reading
                // float3 worldPosition = mul(unity_ObjectToWorld, IN.vertex).xyz;
                // 以地板中心为uv的（0，0）点
                float2 uv = IN.worldPos.xz - _Position.xz;
                
                uv /= (_OrthographicCamSize * 2);
                uv += 0.5;
                // mask to prevent bleeding
                // 在地图边缘做个遮罩，也就是说不会塌陷
                float mask = tex2D(_Mask, uv).a;
                float4 effect = tex2D(_GlobalEffectRT, uv);
                effect *= mask;

                float3 topdownNoise = tex2D(_Noise, IN.worldPos.xz * _NoiseScale).rgb;

                float3 snowtexture = tex2D(_MainTex, IN.worldPos.xz * _SnowTextureScale).rgb;

                float3 baseTexture = tex2D(_MainTexBase, IN.worldPos.xz * _Scale).rgb;

                //// primary texture only on red vertex color with the noise texture
                float vertexColoredPrimary = step(0.6 * topdownNoise, IN.color.r).r;
                float3 snowTextureResult = vertexColoredPrimary * snowtexture;

                //// edge for primary texture
                float vertexColorEdge = ((step((0.6 - _Edgewidth) * topdownNoise, IN.color.r)) * (1 -
                    vertexColoredPrimary)).r;

                //// basetexture only where there is no red vertex paint
                float3 baseTextureResult = baseTexture * (1 - (vertexColoredPrimary + vertexColorEdge));
                //// main colors by adding everything together
                float3 mainColors = (baseTextureResult + ((snowTextureResult * _SnowTextureOpacity) + (
                    vertexColoredPrimary * _Color)) + (vertexColorEdge * _EdgeColor));
                ////lerp the colors using the RT effect path 
                mainColors = saturate(lerp(mainColors, _PathColor * effect.g * 2,
                                           saturate(effect.g * 3 * vertexColoredPrimary))).rgb;


                // add shadows
                float4 shadowCoord = TransformWorldToShadowCoord(IN.worldPos);
                #if _MAIN_LIGHT_SHADOWS_CASCADE || _MAIN_LIGHT_SHADOWS
								Light mainLight = GetMainLight(shadowCoord);
                #else
                Light mainLight = GetMainLight();
                #endif
                float shadows = mainLight.shadowAttenuation;
                float4 litMainColors = float4(mainColors, 1) * (shadows);
                // add in the sparkles
                // sparkles, static multiplied by a simple screenpos version
                float sparklesStatic = tex2D(_SparkleNoise, IN.worldPos.xz * _SparkleScale * 5).r;
                // float sparklesResult = tex2D(_SparkleNoise, IN.worldPos.xz * _SparkleScale * 5).r * sparklesStatic;
                float sparklesResult = tex2D(_SparkleNoise, (IN.worldPos.xz + IN.screenPos) * _SparkleScale) *
                    sparklesStatic;
                litMainColors += step(_SparkCutoff, sparklesResult) * _SparklesIntensity * vertexColoredPrimary;
                // add rim light
                half rim = 1.0 - dot((IN.viewDir), IN.normal);
                litMainColors += vertexColoredPrimary * _RimColor * pow(rim, _RimPower);


                // ambient and mainlight colors added
                half4 extraColors;
                extraColors.rgb = litMainColors * mainLight.color.rgb * (shadows + unity_AmbientSky);
                extraColors.a = 1;

                // everything together
                float4 final = litMainColors + extraColors;
                // add in fog
                final.rgb = MixFog(final.rgb, IN.fogFactor);
                return final;
            }
            ENDHLSL

        }


        // shadow casting pass with empty fragment
        Pass
        {

            Tags
            {
                "LightMode" = "ShadowCaster"
            }


            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma fragment frag
            half4 frag(Varyings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }
}