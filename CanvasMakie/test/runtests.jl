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

        # unimplemented atomic plots are a LOUD error, never a blank render
        # (scatter is not implemented until D-003)
        scatter!(Axis(fig[1, 1]), [0.0, 1.0], [0.0, 1.0])
        @test_throws Exception Makie.colorbuffer(fig)
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

        # per-vertex colors are a loud unimplemented error (draw_multi, D-008)
        scene6 = Scene(size = (100, 100), backgroundcolor = :white, camera = campixel!)
        lines!(scene6, [10.0, 90.0], [50.0, 50.0]; color = [:red, :blue], linewidth = 8)
        @test_throws Exception Makie.colorbuffer(CanvasMakie.Screen(scene6))
    end
end
