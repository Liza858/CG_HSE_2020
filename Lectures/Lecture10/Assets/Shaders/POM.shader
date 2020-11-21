﻿﻿﻿Shader "Custom/POM"
{
    Properties {
        // normal map texture on the material,
        // default to dummy "flat surface" normalmap
        [KeywordEnum(PLAIN, NORMAL, BUMP, POM, POM_SHADOWS)] MODE("Overlay mode", Float) = 0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _MainTex("Texture", 2D) = "grey" {}
        _HeightMap("Height Map", 2D) = "white" {}
        _MaxHeight("Max Height", Range(0.0001, 0.02)) = 0.01
        _StepLength("Step Length", Float) = 0.000001
        _MaxStepCount("Max Step Count", Int) = 64
        
        _Reflectivity("Reflectivity", Range(1, 100)) = 0.5
    }
    
    CGINCLUDE
// Upgrade NOTE: excluded shader from DX11; has structs without semantics (struct v2f members bitangent)
#pragma exclude_renderers d3d11
    #include "UnityCG.cginc"
    #include "UnityLightingCommon.cginc"
    
    inline float LinearEyeDepthToOutDepth(float z)
    {
        return (1 - _ZBufferParams.w * z) / (_ZBufferParams.z * z);
    }

    struct v2f {
        float3 worldPos : TEXCOORD0;
        half3 worldSurfaceNormal : TEXCOORD4;
        // texture coordinate for the normal map
        float2 uv : TEXCOORD5;
        float4 clip : SV_POSITION;
        half3 bitangent : TEXCOORD1;
        half3 tangent : TEXCOORD2;
        half3 normal : TEXCOORD3;
    };

    // Vertex shader now also gets a per-vertex tangent vector.
    // In Unity tangents are 4D vectors, with the .w component used to indicate direction of the bitangent vector.
    v2f vert (float4 vertex : POSITION, float3 normal : NORMAL, float4 tangent : TANGENT, float2 uv : TEXCOORD0)
    {
        v2f o;
        o.clip = UnityObjectToClipPos(vertex);
        o.worldPos = mul(unity_ObjectToWorld, vertex).xyz;
        half3 wNormal = UnityObjectToWorldNormal(normal);
        half3 wTangent = UnityObjectToWorldDir(tangent.xyz);
        
        o.uv = uv;
        o.worldSurfaceNormal = normal;
        
        // compute bitangent from cross product of normal and tangent and output it

        o.normal = wNormal;
        o.tangent = wTangent;
        o.bitangent = UnityObjectToWorldDir(normalize(tangent.w * cross(normal, tangent)));
        
        return o;
    }

    // normal map texture from shader properties
    sampler2D _NormalMap;
    sampler2D _MainTex;
    sampler2D _HeightMap;
    
    // The maximum depth in which the ray can go.
    uniform float _MaxHeight;
    // Step size
    uniform float _StepLength;
    // Count of steps
    uniform int _MaxStepCount;
    
    float _Reflectivity;

    void frag (in v2f i, out half4 outColor : COLOR, out float outDepth : DEPTH)
    {
        float2 uv = i.uv;
        
        float3 worldViewDir = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);
#if MODE_BUMP
        // Change UV according to the Parallax Offset Mapping
        half3 dir = normalize(half3(dot(i.tangent, worldViewDir), dot(i.bitangent, worldViewDir), dot(i.normal, worldViewDir)));
        float h = _MaxHeight * (1-tex2D(_HeightMap, uv).x);
        uv -= h * dir.xy / dir.z;
#endif   
    
        float depthDif = 0;
#if MODE_POM | MODE_POM_SHADOWS    
        // Change UV according to Parallax Occclusion Mapping

        half3 dir = normalize(half3(dot(i.tangent, worldViewDir), dot(i.bitangent, worldViewDir), dot(i.normal, worldViewDir)));
        half3 pos = half3(0, 0, 0);
        half3 prev = half3(0, 0, 0);
        float prev_dh = 0;
        float dh = 0;
        float h = 0;
        

        bool flag = true;
        for (int step = 0; step < _MaxStepCount; ++step) {
	     if (flag) {
		 prev = pos;
		 pos = _StepLength * step * (-dir); 
		 prev_dh = dh;
		 h = _MaxHeight * tex2D(_HeightMap, uv + pos.xy).x;
		 dh = abs(h - pos.z);
		 if (h < pos.z) {
		    flag = false;
		 }
	     }
        }

        uv += lerp(pos.xy, prev.xy, dh / (dh + prev_dh)); // интерполяция
#endif

        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
        float shadow = 0;
#if MODE_POM_SHADOWS
        // Calculate soft shadows according to Parallax Occclusion Mapping, assign to shadow
#endif
        
        half3 normal = i.worldSurfaceNormal;
#if !MODE_PLAIN
        // Implement Normal Mapping

        half3 color = UnpackNormal(tex2D(_NormalMap, uv));
        normal = normalize(color.x * i.tangent + color.y * i.bitangent + color.z * i.normal);
#endif

        // Diffuse lightning
        half cosTheta = max(0, dot(normal, worldLightDir));
        half3 diffuseLight = max(0, cosTheta) * _LightColor0 * max(0, 1 - shadow);
        
        // Specular lighting (ad-hoc)
        half specularLight = pow(max(0, dot(worldViewDir, reflect(worldLightDir, normal))), _Reflectivity) * _LightColor0 * max(0, 1 - shadow); 

        // Ambient lighting
        half3 ambient = ShadeSH9(half4(UnityObjectToWorldNormal(normal), 1));

        // Return resulting color
        float3 texColor = tex2D(_MainTex, uv);
        outColor = half4((diffuseLight + specularLight + ambient) * texColor, 0);
        outDepth = LinearEyeDepthToOutDepth(LinearEyeDepth(i.clip.z));
    }
    ENDCG
    
    SubShader
    {    
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "ForwardBase" }
        
            ZTest Less
            ZWrite On
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_local MODE_PLAIN MODE_NORMAL MODE_BUMP MODE_POM MODE_POM_SHADOWS
            ENDCG
            
        }
    }
}