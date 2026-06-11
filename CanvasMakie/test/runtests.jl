using Test
using Makie
using CanvasMakie
using ColorTypes
using FixedPointNumbers

const HAVE_RENDERER = CanvasMakie.renderer_available()

@testset "Screen protocol (D-001)" begin
    scene = Scene(size = (120, 80), backgroundcolor = :red, camera = campixel!)
    screen = CanvasMakie.Screen(scene)
    @test screen isa Makie.MakieScreen
    @test size(screen) == (120, 80)
    @test Makie.px_per_unit(screen) == 1.0
    @test Makie.backend_showable(CanvasMakie.Screen, MIME"image/png"())
    @test !Makie.backend_showable(CanvasMakie.Screen, MIME"image/svg+xml"())

    # px_per_unit from screen_config kwargs (through merge_screen_config)
    screen2x = CanvasMakie.Screen(scene; px_per_unit = 2)
    @test Makie.px_per_unit(screen2x) == 2.0
    @test size(screen2x) == (240, 160)

    # apply_screen_config! swaps config + scene
    cfg = CanvasMakie.ScreenConfig(3.0, true)
    Makie.apply_screen_config!(screen2x, cfg, scene)
    @test Makie.px_per_unit(screen2x) == 3.0

    # io/path + storage-format constructors collapse to the image screen
    @test CanvasMakie.Screen(scene, cfg, nothing, MIME"image/png"()) isa CanvasMakie.Screen
    @test CanvasMakie.Screen(scene, cfg, Makie.JuliaNative) isa CanvasMakie.Screen
end

@testset "empty-scene render e2e (D-001)" begin
    if !HAVE_RENDERER
        @test_skip "headless renderer unavailable"
    else
        # solid-red scene → every probed pixel is red, at both scale factors
        scene = Scene(size = (120, 80), backgroundcolor = :red, camera = campixel!)
        screen = CanvasMakie.Screen(scene)
        img = Makie.colorbuffer(screen)
        @test size(img) == (80, 120)  # (h, w)
        @test img[1, 1] == RGBA{N0f8}(1, 0, 0, 1)
        @test img[40, 60] == RGBA{N0f8}(1, 0, 0, 1)
        @test img[80, 120] == RGBA{N0f8}(1, 0, 0, 1)

        screen2x = CanvasMakie.Screen(scene; px_per_unit = 2)
        img2 = Makie.colorbuffer(screen2x)
        @test size(img2) == (160, 240)
        @test img2[80, 120] == RGBA{N0f8}(1, 0, 0, 1)

        # backend_show writes a real PNG of the right dimensions
        io = IOBuffer()
        Makie.backend_show(screen, io, MIME"image/png"(), scene)
        png = take!(io)
        @test png[1:8] == UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

        # an empty Figure renders through the full Makie display path
        CanvasMakie.activate!()
        fig = Figure(size = (100, 60))
        figimg = Makie.colorbuffer(fig)
        @test size(figimg) == (60, 100)
        @test figimg[30, 50] == RGBA{N0f8}(1, 1, 1, 1)  # default white background

        # `show` through Makie's display machinery (the getscreen path)
        io2 = IOBuffer()
        show(io2, MIME"image/png"(), fig)
        png2 = take!(io2)
        @test png2[1:8] == UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

        # as of D-006 a complete Axis (spines, grids, tick labels = lines +
        # text plots) renders end-to-end — the original D-001 expectation
        # (loud error on unimplemented plots) is now exercised by meshscatter
        ax = Axis(fig[1, 1])
        scatter!(ax, [0.0, 1.0], [0.0, 1.0])
        aximg = Makie.colorbuffer(fig)
        @test size(aximg) == (60, 100)
        @test any(px -> px != RGBA{N0f8}(1, 1, 1, 1), aximg)  # axis ink exists

        # unimplemented atomic plots stay LOUD, never a blank render
        fig2 = Figure(size = (100, 60))
        meshscatter!(Axis(fig2[1, 1]), [0.0, 1.0], [0.0, 1.0])
        @test_throws Exception Makie.colorbuffer(fig2)
    end
end

# count of color-distinct runs along a pixel row — distinguishes solid (1 run)
# from dashed (several runs) without hand-computing dash phase
function dark_runs(img, row, bg)
    runs = 0
    indark = false
    for px in img[row, :]
        d = px != bg
        d && !indark && (runs += 1)
        indark = d
    end
    return runs
end

@testset "lines + linesegments render (D-002)" begin
    if !HAVE_RENDERER
        @test_skip "headless renderer unavailable"
    else
        WHITE = RGBA{N0f8}(1, 1, 1, 1)
        BLACK = RGBA{N0f8}(0, 0, 0, 1)

        # thick horizontal black line through y=50 (pixel-space camera);
        # Makie y-up: data y=50 → image row ~50 from bottom = row 51 of 100
        scene = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        lines!(scene, [10.0, 90.0], [50.0, 50.0]; color = :black, linewidth = 8)
        img = Makie.colorbuffer(CanvasMakie.Screen(scene))
        @test size(img) == (100, 100)
        @test img[50, 50] == BLACK          # on the line
        @test img[50, 5] == WHITE           # left of the line start
        @test img[50, 95] == WHITE          # right of the line end
        @test img[20, 50] == WHITE          # far above
        @test dark_runs(img, 50, WHITE) == 1  # solid: one run

        # NaN breaks the polyline (CairoMakie draw_single_lines semantics)
        scene2 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        lines!(scene2, [10.0, 40.0, NaN, 60.0, 90.0], [50.0, 50.0, NaN, 50.0, 50.0];
               color = :black, linewidth = 8)
        img2 = Makie.colorbuffer(CanvasMakie.Screen(scene2))
        @test img2[50, 25] == BLACK         # first segment
        @test img2[50, 50] == WHITE         # the NaN gap
        @test img2[50, 75] == BLACK         # second segment
        @test dark_runs(img2, 50, WHITE) == 2

        # linesegments: disjoint pairs with a gap between them
        scene3 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        linesegments!(scene3, [10.0, 40.0, 60.0, 90.0], [50.0, 50.0, 50.0, 50.0];
                      color = :black, linewidth = 8)
        img3 = Makie.colorbuffer(CanvasMakie.Screen(scene3))
        @test img3[50, 25] == BLACK
        @test img3[50, 50] == WHITE
        @test img3[50, 75] == BLACK

        # dashed linestyle produces multiple on-runs where solid has one
        scene4 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        lines!(scene4, [10.0, 90.0], [50.0, 50.0]; color = :black, linewidth = 4,
               linestyle = :dash)
        img4 = Makie.colorbuffer(CanvasMakie.Screen(scene4))
        @test dark_runs(img4, 50, WHITE) >= 2

        # colored line: exact rgba lands on canvas
        scene5 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        lines!(scene5, [10.0, 90.0], [50.0, 50.0]; color = :blue, linewidth = 8)
        img5 = Makie.colorbuffer(CanvasMakie.Screen(scene5))
        @test img5[50, 50] == RGBA{N0f8}(0, 0, 1, 1)

        # ── draw_multi (D-008): per-vertex colors and linewidths ──
        # 2-point gradient line red→blue: endpoints near-pure, middle blended
        scene6 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        lines!(scene6, [10.0, 90.0], [50.0, 50.0]; color = [:red, :blue], linewidth = 8)
        img6 = Makie.colorbuffer(CanvasMakie.Screen(scene6))
        r12 = Float64(ColorTypes.red(img6[50, 12]))
        b12 = Float64(ColorTypes.blue(img6[50, 12]))
        r88 = Float64(ColorTypes.red(img6[50, 88]))
        b88 = Float64(ColorTypes.blue(img6[50, 88]))
        @test r12 > 0.9 && b12 < 0.2     # start: red
        @test b88 > 0.9 && r88 < 0.2     # end: blue
        rm_ = Float64(ColorTypes.red(img6[50, 50]))
        bm_ = Float64(ColorTypes.blue(img6[50, 50]))
        @test 0.2 < rm_ < 0.8 && 0.2 < bm_ < 0.8  # middle: blended

        # per-segment colors on linesegments (equal endpoint colors → solid)
        scene7 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        linesegments!(scene7, [10.0, 40.0, 60.0, 90.0], [50.0, 50.0, 50.0, 50.0];
                      color = [:red, :red, :blue, :blue], linewidth = 8)
        img7 = Makie.colorbuffer(CanvasMakie.Screen(scene7))
        @test img7[50, 25] == RGBA{N0f8}(1, 0, 0, 1)
        @test img7[50, 75] == RGBA{N0f8}(0, 0, 1, 1)
        @test img7[50, 50] == WHITE

        # per-segment linewidths on linesegments (pairs must agree)
        scene8 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        linesegments!(scene8, [10.0, 40.0, 60.0, 90.0], [30.0, 30.0, 30.0, 30.0];
                      color = :black, linewidth = [16.0, 16.0, 2.0, 2.0])
        img8 = Makie.colorbuffer(CanvasMakie.Screen(scene8))
        @test img8[64, 25] == BLACK      # thick: 7px above center still inked
        @test img8[64, 75] == WHITE      # thin segment: not at that offset
        @test img8[70, 75] == BLACK      # but inked on its center row

        # color-change mid-polyline strokes runs + gradient bridge
        scene9 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        lines!(scene9, [10.0, 50.0, 90.0], [50.0, 50.0, 50.0];
               color = [:red, :red, :blue], linewidth = 8)
        img9 = Makie.colorbuffer(CanvasMakie.Screen(scene9))
        @test img9[50, 25] == RGBA{N0f8}(1, 0, 0, 1)             # first run solid red
        bm9 = Float64(ColorTypes.blue(img9[50, 85]))
        @test bm9 > 0.8                                           # bridge end ≈ blue
    end
end

@testset "scatter markers render (D-003)" begin
    if !HAVE_RENDERER
        @test_skip "headless renderer unavailable"
    else
        WHITE = RGBA{N0f8}(1, 1, 1, 1)
        RED = RGBA{N0f8}(1, 0, 0, 1)
        BLUE = RGBA{N0f8}(0, 0, 1, 1)
        pxscene() = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        shot(scene) = Makie.colorbuffer(CanvasMakie.Screen(scene))

        # Marker geometry ground truth measured from real CairoMakie 0.15.11
        # (the parity oracle): :circle and :rect are scaled BezierPaths —
        # circle r ≈ 0.3525·markersize; rect half-width ≈ 6.6 at markersize 24
        # (extent 44–57); 45°-rotated rect half-diagonal ≈ 9.5 (extent 41–60).
        blueish(px) = Float64(ColorTypes.blue(px)) > 0.6 && Float64(ColorTypes.red(px)) < 0.4

        # default circle marker, exact fill color in the middle, white outside
        s1 = pxscene()
        scatter!(s1, [50.0], [50.0]; color = :red, markersize = 20)
        img1 = shot(s1)
        @test img1[50, 50] == RED
        @test img1[50, 46] == RED            # r=4, solidly inside r≈7.05
        @test img1[50, 35] == WHITE          # outside
        @test img1[30, 50] == WHITE

        # rect marker (half ≈ 6.6 at ms 24): inside center, outside the corners
        s2 = pxscene()
        scatter!(s2, [50.0], [50.0]; color = :blue, marker = :rect, markersize = 24)
        img2 = shot(s2)
        @test img2[50, 50] == BLUE
        @test img2[45, 45] == BLUE           # |5,5| inside half 6.6
        @test img2[42, 42] == WHITE          # |8,8| outside
        @test img2[50, 59] == WHITE          # dx=9 outside half 6.6
        @test img2[50, 65] == WHITE

        # rotation: the diamond reaches dx=8 on the axis (≤ 9.5) where the
        # unrotated square (half 6.6) does not — and vice versa at |6,6|·√2
        s3 = pxscene()
        scatter!(s3, [50.0], [50.0]; color = :blue, marker = :rect, markersize = 24,
                 rotation = pi / 4)
        img3 = shot(s3)
        @test blueish(img3[50, 58])          # dx≈7.5: inside diamond
        @test blueish(img3[50, 59])          # dx≈8.5: still inside diamond…
        @test !blueish(img2[50, 59])         # …but outside the unrotated square
        @test img3[44, 44] == WHITE          # |6,6| sum 12 > 9.5: outside diamond
        @test img3[50 - 11, 50 + 11] == WHITE

        # BezierPath marker (:utriangle): center filled, region below apex white
        s4 = pxscene()
        scatter!(s4, [50.0], [50.0]; color = :red, marker = :utriangle, markersize = 30)
        img4 = shot(s4)
        @test img4[50, 50] == RED
        @test img4[35, 35] == WHITE          # above-left of the triangle
        @test img4[35, 65] == WHITE          # above-right

        # marker_offset shifts in markerspace
        s5 = pxscene()
        scatter!(s5, [50.0], [50.0]; color = :red, markersize = 16,
                 marker_offset = Makie.Vec2f(25, 0))
        img5 = shot(s5)
        @test img5[50, 75] == RED
        @test img5[50, 50] == WHITE

        # per-point colors (arrays are fine for scatter, unlike lines)
        s6 = pxscene()
        scatter!(s6, [30.0, 70.0], [50.0, 50.0]; color = [:red, :blue], markersize = 16)
        img6 = shot(s6)
        @test img6[50, 30] == RED
        @test img6[50, 70] == BLUE

        # strokewidth + strokecolor ring around the fill.
        # Ground truth measured from real CairoMakie 0.15.11: :circle is a
        # BezierPath of radius 0.3525 (NOT 0.5), so markersize 20 → r ≈ 7.05,
        # and the 4px pen is NOT scaled by the marker matrix → ring ≈ [5, 9].
        s7 = pxscene()
        scatter!(s7, [50.0], [50.0]; color = :white, strokecolor = :blue,
                 strokewidth = 4, markersize = 20)
        img7 = shot(s7)
        @test img7[50, 50] == WHITE          # fill
        @test img7[50, 43] == BLUE           # stroke ring at r≈7
        @test img7[50, 38] == WHITE          # outside the ring (r=12)

        # Char markers are a loud error until the text engine (D-006)
        s8 = pxscene()
        scatter!(s8, [50.0], [50.0]; marker = 'x', markersize = 20)
        @test_throws Exception shot(s8)
    end
end

@testset "heatmap + image render (D-004)" begin
    if !HAVE_RENDERER
        @test_skip "headless renderer unavailable"
    else
        pxscene() = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        shot(scene) = Makie.colorbuffer(CanvasMakie.Screen(scene))
        ch(px) = (Float64(ColorTypes.red(px)), Float64(ColorTypes.green(px)), Float64(ColorTypes.blue(px)))
        ≈ₚ(a, b) = all(abs.(a .- b) .< 0.02)

        # image! with 2×2 primaries — orientation truth measured from real
        # CairoMakie 0.15.11: img[i,j] maps i→x, j→y (y-up), so img[1,1] (red)
        # is the BOTTOM-left quadrant (image row 75, col 25)
        s1 = pxscene()
        img2 = [Makie.RGBAf(1, 0, 0, 1) Makie.RGBAf(0, 1, 0, 1);
                Makie.RGBAf(0, 0, 1, 1) Makie.RGBAf(1, 1, 0, 1)]
        image!(s1, 0 .. 100, 0 .. 100, img2; interpolate = false)
        out1 = shot(s1)
        @test ≈ₚ(ch(out1[75, 25]), (1.0, 0.0, 0.0))   # img[1,1] red
        @test ≈ₚ(ch(out1[75, 75]), (0.0, 0.0, 1.0))   # img[2,1] blue
        @test ≈ₚ(ch(out1[25, 25]), (0.0, 1.0, 0.0))   # img[1,2] green
        @test ≈ₚ(ch(out1[25, 75]), (1.0, 1.0, 0.0))   # img[2,2] yellow

        # heatmap quadrant colors — oracle viridis values from CairoMakie
        s2 = pxscene()
        heatmap!(s2, [0, 50, 100], [0, 50, 100], [1 2; 3 4]; interpolate = false)
        out2 = shot(s2)
        @test ≈ₚ(ch(out2[75, 25]), (0.267, 0.004, 0.329))  # v=1 → viridis(0)
        @test ≈ₚ(ch(out2[75, 75]), (0.208, 0.718, 0.475))  # v=3
        @test ≈ₚ(ch(out2[25, 25]), (0.192, 0.408, 0.557))  # v=2
        @test ≈ₚ(ch(out2[25, 75]), (0.992, 0.906, 0.145))  # v=4

        # irregular grid → slow path (per-cell quads), oracle-pinned probes
        s3 = pxscene()
        heatmap!(s3, [0, 20, 100], [0, 60, 100], [1 2; 3 4])
        out3 = shot(s3)
        @test ≈ₚ(ch(out3[70, 10]), (0.267, 0.004, 0.329))
        @test ≈ₚ(ch(out3[70, 60]), (0.208, 0.718, 0.475))
        @test ≈ₚ(ch(out3[20, 10]), (0.188, 0.408, 0.557))
        @test ≈ₚ(ch(out3[20, 60]), (0.996, 0.906, 0.141))

        # interpolate=true blends at the quadrant seam (exact kernel differs
        # from Cairo's bilinear — assert blending, not exact values)
        s4 = pxscene()
        image!(s4, 0 .. 100, 0 .. 100, img2; interpolate = true)
        out4 = shot(s4)
        mid = ch(out4[50, 50])
        for quad in ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 1.0, 0.0))
            @test !≈ₚ(mid, quad)
        end
    end
end

@testset "poly + walk semantics (D-005)" begin
    if !HAVE_RENDERER
        @test_skip "headless renderer unavailable"
    else
        WHITE = RGBA{N0f8}(1, 1, 1, 1)
        RED = RGBA{N0f8}(1, 0, 0, 1)
        BLUE = RGBA{N0f8}(0, 0, 1, 1)
        GREEN = RGBA{N0f8}(0, N0f8(0.502), 0, 1)  # CSS :green is half-intensity
        pxscene() = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        shot(scene) = Makie.colorbuffer(CanvasMakie.Screen(scene))

        # triangle from points: fill + white outside
        s1 = pxscene()
        poly!(s1, Makie.Point2f[(10, 10), (90, 10), (50, 90)]; color = :red)
        img1 = shot(s1)
        @test img1[80, 50] == RED            # low center (y=20)
        @test img1[40, 50] == RED            # mid (y=60 inside)
        @test img1[80, 12] == WHITE          # outside left of base
        @test img1[15, 15] == WHITE          # top corner outside

        # Rect2 poly with stroke
        s2 = pxscene()
        poly!(s2, Makie.Rect2f(20, 20, 60, 40); color = :blue, strokecolor = :red,
              strokewidth = 4)
        img2 = shot(s2)
        @test img2[50, 50] == BLUE           # inside (data y≈50 → row 50)
        @test img2[40, 22] == RED            # left stroke edge (x=20±2)
        @test img2[40, 10] == WHITE          # outside

        # vector of rects with per-element colors (hist/barplot pattern)
        s3 = pxscene()
        poly!(s3, [Makie.Rect2f(10, 10, 20, 80), Makie.Rect2f(60, 10, 20, 80)];
              color = [:red, :green])
        img3 = shot(s3)
        @test img3[50, 20] == RED
        @test img3[50, 70] == GREEN
        @test img3[50, 45] == WHITE          # gap between bars

        # polygon with a hole (even-odd): hole shows background
        s4 = pxscene()
        outer = Makie.Point2f[(10, 10), (90, 10), (90, 90), (10, 90)]
        hole = Makie.Point2f[(40, 40), (60, 40), (60, 60), (40, 60)]
        poly!(s4, Makie.GeometryBasics.Polygon(outer, [hole]); color = :blue)
        img4 = shot(s4)
        @test img4[80, 20] == BLUE           # solid region
        @test img4[50, 50] == WHITE          # the hole
        @test img4[20, 80] == BLUE

        # z-order: a later-translated plot draws beneath (zvalue2d sort)
        s5 = pxscene()
        p_top = poly!(s5, Makie.Rect2f(20, 20, 60, 60); color = :red)
        p_bot = poly!(s5, Makie.Rect2f(20, 20, 60, 60); color = :blue)
        translate!(p_bot, 0, 0, -1)          # below despite being added later
        img5 = shot(s5)
        @test img5[50, 50] == RED

        # visible = false plots are skipped
        s6 = pxscene()
        p6 = poly!(s6, Makie.Rect2f(20, 20, 60, 60); color = :red, visible = false)
        img6 = shot(s6)
        @test img6[50, 50] == WHITE

        # circle poly
        s7 = pxscene()
        poly!(s7, Makie.Circle(Makie.Point2f(50, 50), 25.0f0); color = :green)
        img7 = shot(s7)
        @test img7[50, 50] == GREEN
        @test img7[50, 30] == GREEN          # r=20 < 25
        @test img7[20, 20] == WHITE          # corner outside

        # band needs mesh (R-005): loud error, not a blank
        s8 = pxscene()
        band!(s8, [10.0, 90.0], [20.0, 20.0], [60.0, 60.0])
        @test_throws Exception shot(s8)
    end
end

@testset "text via glyph outlines (D-006)" begin
    if !HAVE_RENDERER
        @test_skip "headless renderer unavailable"
    else
        pxscene() = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        shot(scene) = Makie.colorbuffer(CanvasMakie.Screen(scene))
        function inkbbox(img; pred = px -> Float64(ColorTypes.red(px)) < 0.5 && Float64(ColorTypes.green(px)) < 0.5)
            dark = [(r, c) for r in 1:size(img, 1), c in 1:size(img, 2) if pred(img[r, c])]
            isempty(dark) && return nothing
            return (extrema(first.(dark)), extrema(last.(dark)), length(dark))
        end
        # oracle ink bboxes measured from real CairoMakie 0.15.11 (glyphs there
        # rasterize via Cairo+FreeType; ours are the same outlines as paths, so
        # bounds should agree within antialiasing tolerance)
        close2(got, want; tol = 3) =
            abs(got[1] - want[1]) <= tol && abs(got[2] - want[2]) <= tol
        function bbox_close(got, want; tol = 3, inktol = 0.3)
            got === nothing && return false
            return close2(got[1], want[1]; tol) && close2(got[2], want[2]; tol) &&
                   abs(got[3] - want[3]) <= inktol * want[3]
        end

        mk(; kw...) = begin
            s = pxscene()
            text!(s, 50.0, 50.0; text = "Hi", fontsize = 40, color = :black, kw...)
            shot(s)
        end

        @test bbox_close(inkbbox(mk()), ((13, 41), (54, 86), 360))
        @test bbox_close(inkbbox(mk(align = (:center, :center))), ((36, 65), (35, 67), 361))
        @test bbox_close(inkbbox(mk(rotation = pi / 2)), ((15, 47), (13, 41), 360))

        # color: red text ink is pure red
        sr = pxscene()
        text!(sr, 50.0, 50.0; text = "H", fontsize = 40, color = :red,
              align = (:center, :center))
        imgr = shot(sr)
        reds = inkbbox(imgr; pred = px -> Float64(ColorTypes.red(px)) > 0.9 &&
                                          Float64(ColorTypes.green(px)) < 0.1)
        @test reds !== nothing && reds[3] > 100

        # the glyph-path cache fills and is reused across renders
        n_cached = length(CanvasMakie._GLYPH_PATH_CACHE)
        @test n_cached >= 3  # H, i (+ dotted i parts share glyphs per font)
        shot(sr)
        @test length(CanvasMakie._GLYPH_PATH_CACHE) == n_cached

        # glow is a loud error when requested, never silently dropped
        sg = pxscene()
        text!(sg, 50.0, 50.0; text = "x", glowwidth = 5, glowcolor = :red)
        @test_throws Exception shot(sg)
    end
end
