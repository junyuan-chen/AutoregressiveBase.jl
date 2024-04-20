@testset "transformation" begin
    Y0 = zeros(10, 2)
    Y = randn(10, 2)
    tr = NoTrend()
    @test nskip(tr) == 0
    detrend!(tr, Y0, Y)
    @test Y0 == Y
    fill!(Y0, 0)
    invdetrend!(tr, Y, Y0)
    @test all(==(0), Y)

    Y0 = zeros(9, 2)
    Y = randn(10, 2)
    tr = FirstDiff()
    @test nskip(tr) == 1
    detrend!(tr, Y0, Y)
    @test Y0 ≈ diff(Y, dims=1)
    Y1 = zeros(9, 2)
    invdetrend!(tr, Y1, Y0)
    @test Y1 ≈ cumsum(Y0, dims=1)

    Y0 = zeros(8, 2)
    Y = randn(10, 2)
    tr = FirstDiff(2)
    @test nskip(tr) == 2
    detrend!(tr, Y0, Y)
    @test Y0 ≈ view(Y,3:10,:) .- view(Y,1:8,:)
    Y1 = zeros(8, 2)
    invdetrend!(tr, Y1, Y0)
    @test Y1[1:2,:] ≈ Y0[1:2,:]
    @test Y1[3:end,:] - Y1[1:end-2,:] ≈ Y0[3:8,:]
end

@testset "DynamicFactor" begin
    data = matread(datafile("lpw_data.mat"))["dataout"]
    tb = Tables.table(data)
    ibal = all(!isnan, data[3:end,:], dims=1)[:]
    ibal = (1:length(ibal))[ibal]
    xbal = data[2:end,1:8]
    f1 = DynamicFactor(xbal, nothing, FirstDiff(), 3, nothing, 4, 4, 1:223)
    @test size(f1.facX) == (222, 5)
    # Compare results with Matlab code from Li, Plagborg-Møller and Wolf (2024)
    # Make modifications in data/src/lpw_savedata.m to get Matlab results
    @test abs.(f1.facX[1,1:3]) ≈
        abs.([0.669750255362180, -1.415042540425748, -0.279535312367630]) atol=1e-10
    @test abs.(f1.facX[10,1:3]) ≈
        abs.([-2.267063090431706, -1.434815860575840, 0.454588283183868]) atol=1e-10
    @test abs.(f1.facX[20,1:3]) ≈
        abs.([7.323931107653098, -4.727910038603926, 1.825862900774614]) atol=1e-10
    @test abs.(f1.facX[221,1:3]) ≈
        abs.([-0.300027230626971, 0.168284777077292, 1.054070197848707]) atol=1e-10
    @test abs.(f1.Λ'[:,1:3]) ≈
        abs.([0.816933524667466   0.877661701684616   0.673038907345591;
        0.211586118251876  -0.797016010137497  -0.195121578082652;
        0.294391325215926   0.084195578852317   0.212593894215132;
        1.388030195340448   1.495730233977966   0.015497277005997;
        1.075675875094696   0.991704176968184   0.151939966515270;
        1.371864827828503  -0.513779766786925  -0.154190698776157;
        0.000282808827547   0.000684102622842   0.000234552180429;
       -0.128279701643663  -0.168769489168454   1.763765804567798]) atol=1e-10
    @test f1.u[1:8,end] ≈
        [-0.975415737426374, -1.412518101895273, -1.994916116989259, -1.048416744367444,
         -1.093584435914863, -0.217932197392372, -0.927498314077866, -1.269794438833060
        ] atol=1e-10
    @test f1.arcoef' ≈
        [0.736964838253279   0.216046718510706   0.031400816622726  -0.055512886991835;
         0.754170105533859   0.128560903554997   0.094147365408704  -0.071278429940820;
         0.914728014043238  -0.139294004432957   0.104859589673747   0.048585759489537;
         0.623955768161770   0.120327956139262   0.033709249938343  -0.059589528011958;
         1.075841476634743  -0.006232388714530  -0.054906986294867  -0.110350444768725;
         1.264562793369892  -0.138543195394575  -0.175856436931966  -0.016666483863437;
         0.502103927024850   0.100605789022884   0.060796568132528  -0.058813198639289;
         0.998861622995029  -0.043270565241107   0.067670952611482  -0.109591180672500
        ] atol=1e-10
    @test f1.σ ≈ [2.551851358100894, 0.740766400455260, 0.566134049898459,
        1.206309600482594, 1.031873591284054, 3.113219352996401, 0.003014397428756,
        0.528899210498389] atol=1e-10

    f11 = deepcopy(f1)
    fill!(f11.f.fac, 0)
    fill!(f11.Λ, 0)
    fill!(f11.arcoef, 0)
    fit!(f11)
    @test f11.f.fac ≈ f1.f.fac
    @test f11.Λ ≈ f1.Λ
    @test f11.arcoef ≈ f1.arcoef

    @test sprint(show, f1) ==
        "222×3 DynamicFactor{Float64, FirstDiff, Nothing, Factor{Float64, SDDcache{Float64}}, Nothing}"
    if VERSION >= v"1.7"
    @test sprint(show, MIME("text/plain"), f1, context=:displaysize=>(10,120)) == """
        222×3 DynamicFactor{Float64, FirstDiff, Nothing, Factor{Float64, SDDcache{Float64}}, Nothing} with 3 unobserved factors and 0 observed factor:
          -0.66975  1.41504  0.279535
           ⋮                 
          Idiosyncratic AR coefficients for 4 lags:
          ⋮      ⋱  
         Evolution of factors:
          Not estimated"""
    end

    w = data[2:end,1:1]
    f2 = DynamicFactor(xbal, w, FirstDiff(), 4, nothing, 4, 4, 1:223, arexclude=(1,))
    @test abs.(f2.facX[10,1:4]) ≈ abs.([2.647070534273070, -0.409233763390545,
        -2.448583354331101, 0.777062133958662]) atol=1e-10
    @test abs.(f2.Λ[1:4,:]') ≈ abs.([
        1.000000000000000  -0.000000000000085  -0.000000000000253  -0.000000000000277;
       -0.176869660254340   0.341326133790815  -0.531832560474252  -0.050548484398590;
        0.138280288564886   0.176289518804467  -0.003579973854560   0.127784818344253;
       -0.017376912623149   1.389248038370042   1.590214827285696   0.053961254580756;
       -0.288853468488554   1.295956580093574   1.340073720674857   0.376761035586924;
        0.741342427554159   0.746936517706743  -0.836747380775329  -0.637279129786421;
       -0.000057553428649   0.000331665615867   0.000731261496305   0.000272838958179;
       -0.146403622040140  -0.016342164982163   0.008833758737728   1.871736796403937
    ]) atol=1e-10
    @test f2.arcoef' ≈
        [               0                   0                   0                   0;
        0.616037967310018   0.107591400424874   0.069023223680326   0.043873141740624;
        0.769836475718294  -0.022464276053618   0.061128324277641   0.072377642177374;
        0.573263857098401   0.120224782292888   0.044175367824055  -0.054197784792354;
        0.746501793004697   0.124187288728450   0.044444174053458  -0.125784699949580;
        1.030744790868324   0.093747757564231  -0.116526277928615  -0.082567084371622;
        0.511383934328558   0.102277378712291   0.059272962038230  -0.059105468722871;
        0.560208207607704   0.105367527318873   0.098177242590535  -0.027960067387970
        ] atol=1e-10
    @test f2.σ[2:end] ≈ [0.412619331990811, 0.617549404907423, 1.252061775182155,
        1.315822943598192, 3.738078775682554, 0.002967937991064, 0.615717221130628
        ] atol=1e-10

    f21 = deepcopy(f2)
    fill!(f21.Y0, 0)
    fill!(f21.facobs0, 0)
    fill!(f21.f.fac, 0)
    fill!(f21.arcoef, 0)
    fit!(f21, arexclude=1)
    @test f21.f.fac ≈ f2.f.fac
    @test f21.Λ ≈ f2.Λ
    @test f21.arcoef ≈ f2.arcoef

    f3 = fit(DynamicFactor, tb, ibal, nothing, FirstDiff(), BaiNg(30),
        VAROLS, 4, 4, 1:224; subset=(1:224).>1)
    @test abs.(f3.facX[1,1:3]) ≈
        abs.([2.633579135057327, -4.515438104711660, 0.967695227734307]) atol=1e-10
    @test abs.(f3.facX[20,1:3]) ≈
        abs.([-11.213179331809721, -10.755437451370934, -9.740548002249279]) atol=1e-10
    # Li, Plagborg-Møller and Wolf (2024) has an initial row of zeros
    # for lagmatrix generated from cumsum_nan
    # Removing the initial row yields the same estimates here
    @test abs.(coef(f3.facproc)) ≈
        abs.([0.673856090754789  -0.081037456424403  -0.490680042824428;
         1.616377319397290   0.296011178122282  -0.131965176312504;
        -0.244663060538245   1.369015986230120  -0.098455471141018;
         0.283991836982538  -0.195631889289281   0.932725936459795;
        -0.732635002010108  -0.277190250747602   0.179818440183486;
         0.364379235288969  -0.499477715914352  -0.079759252139077;
        -0.055844609138274   0.032057475641071  -0.021067035288564;
         0.259088832362754   0.121301115717096   0.056402897635998;
        -0.072960531361710   0.273201943623642   0.210890285510650;
         0.112900500553000  -0.017828891944840   0.191598679035541;
        -0.215963192051662  -0.118458036521081  -0.102091302758074;
         0.026271389380724  -0.163505737633263  -0.041529088862164;
        -0.179952139267754   0.145787466313025  -0.151287681694109]) atol=1e-10
    @test sprint(show, f3) ==
        "222×3 DynamicFactor{Float64, FirstDiff, Nothing, Factor{Float64, SDDcache{Float64}}, VAROLS{Float64, Vector{Float64}, Nothing, Nothing, Nothing}}"
    if VERSION >= v"1.7"
    @test sprint(show, MIME("text/plain"), f3, context=:displaysize=>(10,120)) == """
        222×3 DynamicFactor{Float64, FirstDiff, Nothing, Factor{Float64, SDDcache{Float64}}, VAROLS{Float64, Vector{Float64}, Nothing, Nothing, Nothing}} with 3 unobserved factors and 0 observed factor:
          2.63358  4.51544  -0.967695
          ⋮                 
          Idiosyncratic AR coefficients for 4 lags:
          ⋮      ⋱  
         Evolution of factors:
          218×13 OLS regression for VAR with 3 variables and 4 lags"""
    end
end
