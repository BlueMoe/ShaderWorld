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
			float _SeaNumSteps;

			float hash(float2 p);
			float map_detailed(float3 p);
			float map_detailed2(float3 p);
			float sea_octave(float2 uv, float choppy);
			float heightMapTracing(float3 ori, float3 dir, out float3 p);
			float3 getNormal(float3 p, float eps);
			float3 getSeaColor(float3 p, float3 n, float3 l, float3 eye, float3 dist);
			float3 getSkyColor(float3 e);
			float diffuse(float3 n, float3 l, float p);
			float specular(float3 n, float3 l, float3 e, float s);

			float heightMapTracing(float3 ori, float3 dir, out float3 p)
			{
				float tm = 0.0;
				float tx = 1000.0;
				float hx = map_detailed2(ori + dir * tx);
				if (hx > 0.0) return tx;
				float hm = map_detailed2(ori + dir * tm);
				float tmid = 0.0;
				for (int i = 0; i < 8; i++) {
					tmid = lerp(tm, tx, hm / (hm - hx));
					p = ori + dir * tmid;
					float hmid = map_detailed2(p);
					if (hmid < 0.0) {
						tx = tmid;
						hx = hmid;
					}
					else {
						tm = tmid;
						hm = hmid;
					}
				}
				return tmid;
			}

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
				float3 n;
				n.y = map_detailed(p);
				n.x = map_detailed(float3(p.x + eps, p.y, p.z)) - n.y;
				n.z = map_detailed(float3(p.x, p.y, p.z + eps)) - n.y;
				n.y = eps;
				return normalize(n);
			}
			float map_detailed(float3 p)
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
					d = sea_octave((uv + _Time.y * _SeaSpeed)*freq, choppy);
					d += sea_octave((uv - _Time.y * _SeaSpeed)*freq, choppy);
					h += d * amp;
					uv = mul(uv, float2x2(1.6, 1.2, -1.2, 1.6));
					freq *= 1.9;
					amp *= 0.22;
					choppy = lerp(choppy, 1.0, 0.2);
				}
				return p.y - h;
			}
			float map_detailed2(float3 p)
			{
				float freq = _SeaFreq;
				float amp = _SeaHeight;
				float choppy = _SeaChoppy;
				float2 uv = p.xz;
				uv.x *= 0.75;

				float d = 0.0;
				float h = 0.0;
				for (int i = 0; i < 3; i++)
				{
					d = sea_octave((uv + _Time.y * _SeaSpeed)*freq, choppy);
					d += sea_octave((uv - _Time.y * _SeaSpeed)*freq, choppy);
					h += d * amp;
					uv = mul(uv, float2x2(1.6, 1.2, -1.2, 1.6));
					freq *= 1.9;
					amp *= 0.22;
					choppy = lerp(choppy, 1.0, 0.2);
				}
				return p.y - h;
			}
			

			float sea_octave(float2 uv, float choppy) 
			{
				uv += noise(uv);
				float2 wv = 1.0 - abs(sin(uv));
				float2 swv = abs(cos(uv));
				wv = lerp(wv, swv, wv);
				return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
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
				o.vertex = mul(UNITY_MATRIX_MVP, v.vertex);
				o.uv = ComputeScreenPos(o.vertex);

				o.uv = o.uv - 3.0;
				o.uv.x *= _ScreenParams.x / _ScreenParams.y;
				return o;
			}

			fixed4 frag(v2f i) : SV_Target
			{
				fixed4 col;
				
				float3 ori = float3(0.0, 3.5, 0);
				float3 dir = normalize(float3(i.uv.xy, -2.0));
				dir.z += length(i.uv) * 0.15;
				//dir = normalize(dir);

				float3 p = float3(0,0,0);
				float x = heightMapTracing(ori, dir, p);
				float3 dist = p - ori;
				float3 n = getNormal(p, dot(dist, dist) * 0.1/ _ScreenParams.x);
				float3 light = normalize(float3(0.0, 1.0, 0.8));

				float3 color = lerp(
					getSkyColor(dir),
					getSeaColor(p, n, light, dir, dist),
					pow(smoothstep(0.0, -0.05, dir.y), 0.3));

				col = fixed4(pow(color, float3(0.75, 0.75, 0.75)), 1.0);

				return col;
			}
			ENDCG
		}
	}
}
