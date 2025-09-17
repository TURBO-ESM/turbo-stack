
#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <tripolar_grid.h>

using namespace turbo;

int main(int argc, char* argv[])
{
    amrex::Initialize(argc, argv);
    {
        // Simple unit cube geometry
        const double x_min = 0.0;
        const double x_max = 1.0;
        const double y_min = 0.0;
        const double y_max = 1.0;
        const double z_min = 0.0;
        const double z_max = 1.0;
        CartesianGeometry geom(x_min, x_max, y_min, y_max, z_min, z_max);
        // Construct with 2 cells in each direction
        const std::size_t n_cell_x = 4;
        const std::size_t n_cell_y = 8;
        const std::size_t n_cell_z = 16;
        auto grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);
        // Construct tripolar grid based on the Cartesian grid
        TripolarGrid fields(grid);

        //const std::size_t n_cell_x = 16;
        //const std::size_t n_cell_y = 8;
        //const std::size_t n_cell_z = 4;
        //TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

        fields.InitializeScalarMultiFabs([](double x, double y, double z) {
            return x;
        });

        fields.InitializeVectorMultiFabs([](double x, double y, double z) {
            return std::array<double, 3>{x, y, z};
        });

        fields.WriteHDF5("tripolar_grid.h5");

    }
    amrex::Finalize();
    return 0;
}