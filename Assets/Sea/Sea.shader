Shader "Unlit/Sea"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_IterFragment("Frag Step", Int) = 5
		_SeaHeight("Height", Range(0.01, 10)) = 0.6
		_SeaChoppy("Choppy", Range(0.01, 10)) = 4
		_SeaSpeed("Speed", Range(0.01, 10)) = 0.8
		_SeaFreq("Freq", Range(0.01, 10)) = 0.16
		_SeaBase("Base", Vector) = (0.1,0.19,0.22)
		_SeaWaterColor("Water Color", Vector) = (0.8,0.9,0.6)
		_SeaNumSteps("Step", Range(1,10)) = 8
		_SeaDirection("Direction",Vector) = (1,1,1)
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" }
		LOD 100

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fog
			#pragma enable_d3d11_debug_symbols 
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				UNITY_FOG_COORDS(1)
				float4 vertex : SV_POSITION;
				float4 pos : TEXCOORD1;
				float4 viewVector : TEXCOORD2;
				float4 normal:NORMAL;
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;
			
			float _IterFragment;
			float _SeaHeight;
			float _SeaChoppy;
			float _SeaSpeed;
			float _SeaFreq;
			float4 _SeaBase;
			float4 _SeaWaterColor;
			float3 _SeaDirection;
			float _SeaNumSteps;
			int _SeaVertexNum;

			float hash(float2 p);
			float SeaWave(float3 p);
			float SineWave(float2 uv, float choppy);
			float3 getNormal(float3 p, float eps);
			float3 getSeaColor(float3 p, float3 n, float3 l, float3 eye, float3 dist);
			float3 getSkyColor(float3 e);
			float diffuse(float3 n, float3 l, float p);
			float specular(float3 n, float3 l, float3 e, float s);
			float3 Gerstner(float3 p, float3 direction, float lambda);

			float noise(in float2 p) 
			{
				float2 i = floor(p);
				float2 f = frac(p);
				float2 u = f*f*(3.0 - 2.0*f);
				return -1.0 + 2.0*lerp(
					lerp(hash(i + float2(0.0, 0.0)),
						hash(i + float2(1.0, 0.0)), u.x),
					lerp(hash(i + float2(0.0, 1.0)),
						hash(i + float2(1.0, 1.0)), u.x), u.y
					);
			}
			float3 getNormal(float3 p, float eps) 
			{
				float3 n = float3(0,0,0);
				//n.y = map_detailed(p);
				//n.x = map_detailed(float3(p.x + eps, p.y, p.z)) - n.y;
				//n.z = map_detailed(float3(p.x, p.y, p.z + eps)) - n.y;
				//n.y = eps;
				return normalize(n);
			}
			float SeaWave(float3 p)
			{
				float freq = _SeaFreq;
				float amp = _SeaHeight;
				float choppy = _SeaChoppy;
				float2 uv = p.xz;
				uv.x *= 0.75;

				float d = 0.0;
				float h = 0.0;
				for (int i = 0; i < 5; i++)
				{
					d = SineWave((uv + _Time.y * _SeaSpeed)*freq, choppy);
					d += SineWave((uv - _Time.y * _SeaSpeed)*freq, choppy);
					h += d * amp;									//累加多个波的效果
					uv = mul(uv, float2x2(1.6, 1.2, -1.2, 1.6));	//(x,z) => (1.6x-1.2z, 1.2x + 1.6z)
					freq *= 1.9;									//正弦波频率递增
					amp *= 0.22;									//波对顶点y轴的影响递减
					choppy = lerp(choppy, 1.0, 0.2);				//起伏权值递减
				}
				return p.y - h;
			}

			float SineWave(float2 uv, float choppy)
			{
				uv += noise(uv);
				uv = sin(uv) * 0.5 + 0.5;
				return pow(1.0 - pow(uv.x * uv.y, 0.66), choppy);
			}
			float hash(float2 p) 
			{
				float h = dot(p, float2(127.1, 311.7));
				return frac(sin(h)*43758.5453123);
			}

			float3 getSkyColor(float3 e)
			{
				e.y = max(e.y, 0.0);
				return float3(pow(1.0 - e.y, 2.0), 1.0 - e.y, 0.6 + (1.0 - e.y)*0.4);
			}

			float diffuse(float3 n, float3 l, float p)
			{
				return pow(dot(n, l) * 0.4 + 0.6, p);
			}

			float3 getSeaColor(float3 p, float3 n, float3 l, float3 eye, float3 dist) 
			{
				float fresnel = clamp(1.0 - dot(n, -eye), 0.0, 1.0);
				fresnel = pow(fresnel, 3.0) * 0.65;

				float3 reflected = getSkyColor(reflect(eye, n));
				float3 refracted = _SeaBase.xyz + diffuse(n, l, 80.0) * _SeaWaterColor.xyz * 0.12;

				float3 color = lerp(refracted, reflected, fresnel);

				float atten = max(1.0 - dot(dist, dist) * 0.001, 0.0);
				color += _SeaWaterColor.xyz * (p.y - _SeaHeight) * 0.18 * atten;

				float spec = specular(n, l, eye, 60.0);

				color += float3(spec, spec, spec);

				return color;
			}

			float specular(float3 n, float3 l, float3 e, float s)
			{
				float nrm = (s + 8.0) / (3.1415 * 8.0);
				return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
			}

			v2f vert(appdata v)
			{
				v2f o;
				float h = SeaWave(v.vertex.xyz);
				v.vertex.y += h;
				o.vertex = mul(UNITY_MATRIX_MVP, v.vertex);
				o.pos = v.vertex;
				o.viewVector.xyz = _WorldSpaceCameraPos.xyz - v.vertex.xyz;
				return o;
			}

			fixed4 frag(v2f i) : SV_Target
			{
				return fixed4(i.pos.y + 2*float4(0,0.6,0.8,0));
			}
			ENDCG
		}
	}
}
