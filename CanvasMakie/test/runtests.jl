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
        lines!(Axis(fig[1, 1]), [0.0, 1.0], [0.0, 1.0])
        @test_throws Exception Makie.colorbuffer(fig)
    end
end
