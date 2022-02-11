//#ifndef TESSELLATION_CGINC_INCLUDED
//#define TESSELLATION_CGINC_INCLUDED
#if defined(SHADER_API_D3D11) || defined(SHADER_API_GLES3) || defined(SHADER_API_GLCORE) || defined(SHADER_API_VULKAN) || defined(SHADER_API_METAL) || defined(SHADER_API_PSSL)
#define UNITY_CAN_COMPILE_TESSELLATION 1
#   define UNITY_domain                 domain
#   define UNITY_partitioning           partitioning
#   define UNITY_outputtopology         outputtopology
#   define UNITY_patchconstantfunc      patchconstantfunc
#   define UNITY_outputcontrolpoints    outputcontrolpoints
#endif

struct Varyings
{		
    float3 worldPos : TEXCOORD1; // world position built-in value				
    float4 color : COLOR;
    float3 normal : NORMAL;
    float4 vertex : SV_POSITION;
    float2 uv : TEXCOORD0;
    float4 screenPos : TEXCOORD2;
    float3 viewDir : TEXCOORD3;
    float fogFactor : TEXCOORD5;
    float4 shadowCoord              : TEXCOORD7;


};

float _Tess;
float _MaxTessDistance;

struct TessellationFactors
{
    float edge[3] : SV_TessFactor;
    float inside : SV_InsideTessFactor;
};

struct Attributes
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
   
};

struct ControlPoint
{
    float4 vertex : INTERNALTESSPOS;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
    float3 normal : NORMAL;
  
};

[UNITY_domain("tri")]
[UNITY_outputcontrolpoints(3)]
[UNITY_outputtopology("triangle_cw")]
[UNITY_partitioning("integer")]
[UNITY_patchconstantfunc("patchConstantFunction")]
ControlPoint hull(InputPatch<ControlPoint, 3> patch, uint id : SV_OutputControlPointID)
{
    return patch[id];
}


float ColorCalcDistanceTessFactor(float4 vertex, float minDist, float maxDist, float tess, float4 color)
{
    float3 worldPosition = mul(unity_ObjectToWorld, vertex).xyz;
    float dist = distance(worldPosition, GetCameraPositionWS());
    float f = clamp(1.0 - (dist - minDist) / (maxDist - minDist), 0.01, 1.0);
  // no tessellation on no red vertex colors
    if (color.r < 0.1)
    {
        f = 0.01;
    }
   
    return f * tess;
}

uniform float3 _Position;
uniform sampler2D _GlobalEffectRT;
uniform float _OrthographicCamSize;

sampler2D _Mask, _Noise;
float _NoiseScale, _SnowHeight, _NoiseWeight, _SnowDepth;

TessellationFactors patchConstantFunction(InputPatch<ControlPoint, 3> patch)
{
    // 至少对摄像机五米内的雪地进行细分
    float minDist = 5.0;
    float maxDist = _MaxTessDistance;
    TessellationFactors f;
    
    float edge0 = ColorCalcDistanceTessFactor(patch[0].vertex, minDist, maxDist, _Tess, patch[0].color);
    float edge1 = ColorCalcDistanceTessFactor(patch[1].vertex, minDist, maxDist, _Tess, patch[1].color);
    float edge2 = ColorCalcDistanceTessFactor(patch[2].vertex, minDist, maxDist, _Tess, patch[2].color);
    
      // make sure there are no gaps between different tessellated distances, by averaging the edges out.
    f.edge[0] = (edge1 + edge2) / 2;
    f.edge[1] = (edge2 + edge0) / 2;
    f.edge[2] = (edge0 + edge1) / 2;
    f.inside = (edge0 + edge1 + edge2) / 3;
    return f;
}

float4 GetShadowPositionHClip(Attributes input)
{
    float3 positionWS = TransformObjectToWorld(input.vertex.xyz);
    float3 normalWS = TransformObjectToWorldNormal(input.normal);

    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, 0));
    
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}

Varyings vert(Attributes input)
{
    Varyings output;

    float3 worldPosition = mul(unity_ObjectToWorld, input.vertex).xyz;
     // Effects RenderTexture Reading
    float2 uv = worldPosition.xz - _Position.xz;
    uv = uv / (_OrthographicCamSize * 2);
    uv += 0.5;
    
    // Mask to prevent bleeding
    float mask = tex2Dlod(_Mask, float4(uv, 0, 0)).a;
    float4 RTEffect = tex2Dlod(_GlobalEffectRT, float4(uv, 0, 0));
    RTEffect *= mask;
				
    float SnowNoise = tex2Dlod(_Noise, float4(worldPosition.xz * _NoiseScale * 5, 0, 0)).r;
    output.viewDir = SafeNormalize(GetCameraPositionWS() - worldPosition);
	// move vertices up where snow is
    input.vertex.xyz += normalize(input.normal) * (saturate((input.color.r * _SnowHeight) + (SnowNoise * _NoiseWeight * input.color.r)));
     // move down where there is a trail from the render texture particles
    input.vertex.xyz -= normalize(input.normal) * saturate(RTEffect.g * saturate(input.color.r)) * _SnowDepth;
   
    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.vertex.xyz);
    

    output.worldPos = vertexInput.positionWS;
#ifdef SHADERPASS_SHADOWCASTER
		output.vertex = GetShadowPositionHClip(input);
 #else
   output.vertex = TransformObjectToHClip(input.vertex.xyz);
 #endif
    
    float4 clipvertex = output.vertex / output.vertex.w;
    output.screenPos = ComputeScreenPos(clipvertex); 
 
   // output.shadowCoord = TransformWorldToShadowCoord(mul(unity_ObjectToWorld, input.vertex).xyz);
    output.shadowCoord = GetShadowCoord(vertexInput);
    // vertex color
    output.color = input.color;
    // adding some noise to the normals, and the path indent
    output.normal = saturate(input.normal * SnowNoise);
    output.normal.y += (RTEffect.g * input.color.r * 0.4);
    output.uv = input.uv;
   
    float fogFactor = ComputeFogFactor(output.vertex.z);
    output.fogFactor = fogFactor;
   
    return output;
}

#define Tesselationing(fieldName) v.fieldName = \
patch[0].fieldName * barycentricCoordinates.x + \
patch[1].fieldName * barycentricCoordinates.y + \
patch[2].fieldName * barycentricCoordinates.z;


[UNITY_domain("tri")]
		Varyings domain(TessellationFactors factors, OutputPatch<ControlPoint, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
{
    Attributes v;
     
	Tesselationing(vertex)
    Tesselationing(uv)
	Tesselationing(color)
	Tesselationing(normal)

    return vert(v);
}


	
