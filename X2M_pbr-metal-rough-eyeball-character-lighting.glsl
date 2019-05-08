//- Allegorithmic Metal/Rough PBR shader
//- ====================================
//-
//- Import from libraries.
import lib-sampler.glsl
import lib-pbr.glsl
import lib-pom.glsl
import lib-utils.glsl

//- Declare the iray mdl material to use with this shader.
//: metadata {
//:   "mdl":"mdl::alg::materials::physically_metallic_roughness::physically_metallic_roughness"
//: }

//- Channels needed for metal/rough workflow are bound here.
//: param auto channel_basecolor
uniform sampler2D basecolor_tex;
//: param auto channel_roughness
uniform sampler2D roughness_tex;
//: param auto channel_metallic
uniform sampler2D metallic_tex;

//: param custom { "default": false, "label": "X2M Tonemapping" , "group": "Piecewise Power Curves" }
uniform bool x2mCurve;

//: param custom { "default": 1.0, "label": "Toe Strength", "min": 0.0, "max": 10.0 ,"group": "Piecewise Power Curves"}
uniform float toeStrength;

//: param custom { "default": 1.0, "label": "Toe Length", "min": 0.0, "max": 10.0 ,"group": "Piecewise Power Curves"}
uniform float toeLength;

//: param custom { "default": 1.0, "label": "Shoulder Strength", "min": 0.0, "max": 10.0 ,"group": "Piecewise Power Curves"}
uniform float shoulderStrength;

//: param custom { "default": 1.0, "label": "ShoulderLength", "min": 0.0, "max": 10.0 ,"group": "Piecewise Power Curves"}
uniform float shoulderLength;

//: param custom { "default": 1.0, "label": "Shoulder Angle", "min": 0.0, "max": 10.0 ,"group": "Piecewise Power Curves"}
uniform float shoulderAngle; 

//: param custom { "default": 1.0, "label": "Gamma", "min": 0.0, "max": 10.0 ,"group": "Piecewise Power Curves"}
uniform float gamma; 


//: param custom { "default": false, "label": "Eye Light" ,"group": "Eye Light"}
uniform bool eye_light;
//: param custom { "default": 1.0, "label": "eye specualr power", "min": 0.0, "max": 5.0 ,"group": "Eye Light"}
uniform float speuclarPower;

//: param auto main_light
uniform vec4 light_main;



vec3 microfacets_brdf( vec3 Nn,	vec3 Ln,vec3 Vn,vec3 Ks,float Roughness)
{
	vec3 Hn = normalize(Vn + Ln);
	float vdh = max( 0.0, dot(Vn, Hn) );
	float ndh = max( 0.0, dot(Nn, Hn) );
	float ndl = max( 0.0, dot(Nn, Ln) );
	float ndv = max( 0.0, dot(Nn, Vn) );
	return fresnel(vdh,Ks) *
		( normal_distrib(ndh,Roughness) * visibility(ndl,ndv,Roughness) / 4.0 );
}



//This code really good but it is related from roughness effect~ not match to this desired result~~~
vec3 eyeLightContribution( vec3 NormalWS,vec3 LightDirWS,	vec3 CameraDirWS, vec3 diffColor , vec3 specColor, float roughness)
{
	return  max(dot(NormalWS,LightDirWS), 0.0) * ( (
		(diffColor*(vec3(1.0,1.0,1.0) - specColor) * M_INV_PI) + microfacets_brdf(NormalWS,LightDirWS,CameraDirWS,	specColor, roughness) ) * M_PI);
}


// X2M Tonemapping

vec3 x2mPiecewiseTonemap(vec3 x)
{
  return x;
}

//- Shader entry point.
void shade(V2F inputs)
{
	// Fetch material parameters, and conversion to the specular/glossiness model
	float roughness = getRoughness(roughness_tex, inputs.tex_coord);
	vec3 baseColor = getBaseColor(basecolor_tex, inputs.tex_coord);
	float metallic = getMetallic(metallic_tex, inputs.tex_coord);
  	vec3 diffColor = generateDiffuseColor(baseColor, metallic);
	vec3 specColor = generateSpecularColor(0.5, baseColor, metallic);
	// Get detail (ambient occlusion) and global (shadow) occlusion factors
	float occlusion = getAO(inputs.tex_coord) * getShadowFactor();
	
	
	//Code block start
	LocalVectors vectors = computeLocalFrame(inputs);	

	//I used very simply method of blinn-phong specular way~
	vec3 normal_vec = computeWSNormal(inputs.tex_coord, inputs.tangent, inputs.bitangent, inputs.normal);
	
	//Very important thing as inputs.position that is from application inputs method
	vec3 eye_vec = is_perspective ? normalize(camera_pos - inputs.position) :-camera_dir;
	
	float eyeSpec_ndv = max( 0.0, dot(normal_vec, eye_vec) );
	//As you know Substance painter that could not provide to light direction.
	//Generally Substance painter did not has MainLight as Direction lighing kind of game engines's Sun lights~~~.
	//Virtual light vector created via uniform value as vector3 data also already defined at above code line~
	// Say again ~ inputs.position is very important stuff~
	vec3 LightVec = normalize(light_main.xyz*100.0 - inputs.position);
	float eyeSpec = pow(eyeSpec_ndv,speuclarPower * 256.0);

	//hm.... Why I defined ndotl?
	//Well... generaly this screen space specular do not affect from shadow now then also not affected from opposite side from directiona lighting.
	//So I made simplle mask....
	//ndotl is really good way for the simple mask for the occlusions with specular ~
	float ndotl =  max( 0.0, dot(normal_vec, LightVec) );
	eyeSpec = mix(0.0 , eyeSpec , ndotl);
	//-- Code block end for the screen space simple specular~

	vec3 eyeFakeSpecular_lightContrib = mix(vec3(0.0,0.0,0.0) , eyeLightContribution(normal_vec, eye_vec, eye_vec, vec3(0.0,0.0,0.0),specColor, roughness) , ndotl);

	// Feed parameters for a physically based BRDF integration
	//vec4 color = pbrComputeBRDF(inputs, diffColor, specColor, glossiness, occlusion);
  
  

  float specOcclusion = specularOcclusionCorrection(occlusion, metallic, roughness);
  vec3 Emissive = pbrComputeEmissive(emissive_tex, inputs.tex_coord).rgb;
	vec3 SpecularShading = specOcclusion * pbrComputeSpecular(vectors, specColor, roughness);
	vec3 DiffuseShading = occlusion * envIrradiance(vectors.normal);
	vec3 color = Emissive + diffColor * DiffuseShading + SpecularShading;


	if(eye_light)
	{
		color += (eyeSpec + eyeFakeSpecular_lightContrib );
	}

	
	if (x2mCurve)
	{
		color = x2mPiecewiseTonemap(color);
	}
	emissiveColorOutput(pbrComputeEmissive(emissive_tex, inputs.tex_coord));
	albedoOutput(color.rgb);
	diffuseShadingOutput(vec3(1.0));
	specularShadingOutput(vec3(0.0));
}


