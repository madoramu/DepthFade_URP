Shader "Unlit/Barrier"
{
    Properties
    {
        _MainTex("MainTexture", 2D) = "white" {}
        _NormalTex("ノーマルマップ", 2D) = "bump" {}
        _NormalMul("ノーマルマップの強さ", float) = 1
        _FresnelColor("リムライトの色", Color) = (1, 1, 1, 1)
        _FresnelPow("フレネルべき乗値", float) = 2
        _FresnelMul("フレネル乗算値", float) = 1
        _DepthIntersectColor("デプスフェードの色", Color) = (1, 1, 1, 1)
        _DepthFadeMul("デプスフェードの強さ", float) = 0.2
    }
    SubShader
    {
        // 透明描画。投影は特にしないのでプロジェクターはオフにしておく
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "IgnoreProjector"="True" }
        // カリングオフ, オブジェクトをデプスバッファに書き込まない, シェーダーで計算したアルファを乗算し、既存色には計算したアルファから1引いた値を乗算する(一般的な透過設定)
        Cull Off ZWrite Off Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal: NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                half3 normal : NORMAL;

                float2 uv : TEXCOORD0;
                half3 viewDir : TEXCOORD1;
                float4 screenPosition : TEXCOORD2;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            sampler2D _NormalTex;
            float4 _NormalTex_ST;
            fixed _NormalMul;

            half _FresnelPow;
            half _FresnelMul;
            half4 _FresnelColor;
            // DepthFade(交差)に必要な要素
            sampler2D _CameraDepthTexture;  // デプスバッファ
            half4 _DepthIntersectColor;
            fixed _DepthFadeMul;

            v2f vert (appdata v)
            {
                v2f o;
                // 3次元座標をクリップ空間座標に変換
                o.vertex = UnityObjectToClipPos(v.vertex);
                // テクスチャスケールとオフセットを考慮した値を格納
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

                // ワールド座標系のカメラ方向のベクトルを取得する
                o.viewDir = normalize(WorldSpaceViewDir(v.vertex));
                // ワールド空間上の法線を取得
                o.normal = UnityObjectToWorldNormal(v.normal);
                // クリップ空間座標を元にスクリーンスペースでの位置を求める(xyが0~wの値になる)
                // プラットフォームごとのY座標上下反転問題も修正
                o.screenPosition = ComputeScreenPos(o.vertex);
                // ビュー空間におけるZ値(深度値)をscreenPosition.zに格納
                COMPUTE_EYEDEPTH(o.screenPosition.z);

                return o;
            }

            // リム値の取得
            inline fixed CalculateRim(half3 viewDir, half3 normal, half fPow, half fMul)
            {
                // 視線ベクトルと法線ベクトルの内積を求める
                half inverse = 1 - abs(dot(viewDir, normal));
                // 減衰させるため乗算を行い0~1に丸め込んで返す
                return saturate(pow(inverse, fPow) * fMul);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // メインテクスチャ読み込み
                fixed4 texColor = tex2D(_MainTex, i.uv);

                // リムライト計算
                fixed rim = CalculateRim(i.viewDir, i.normal, _FresnelPow, _FresnelMul);
                
                // デプスフェード計算
                float depth = abs(LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPosition))) - i.screenPosition.z); 
                fixed depthIntersect = saturate(depth / _DepthFadeMul);
                fixed4 depthIntersectColor = (1 - depthIntersect) * _DepthIntersectColor;

                /*
                // 以下はデプスフェード計算をもう少し分かりやすく行ったもの

                // このシェーダーが実行される前のscreenPos上のカメラ深度値を取得する
                float depthSample = tex2Dproj(_CameraDepthTexture, i.screenPosition).r;
                // 深度値をカメラからのワールド空間における距離として取得する(線形化)
                float depth = LinearEyeDepth(depthSample);
                // 頂点シェーダーで求めた深度値を引いて、交差部分の値を求める(0になっていると完全に交差している)
                float screenDepth = abs(depth - i.screenPosition.z);
                // パラメーターに定義した値で交差値を調整して0~1の範囲に丸める
                fixed depthIntersect = saturate(screenDepth / _DepthFadeMul);
                // 1が交差、0が非交差という形にするため1から引いている。その結果に指定した色を反映させている
                fixed4 depthIntersectColor = (1 - depthIntersect) * _DepthIntersectColor;
                */

                // 出力色設定
                fixed4 col = texColor * _FresnelColor * rim + depthIntersectColor;
                return col;
            }
            ENDCG
        }
    }
}
