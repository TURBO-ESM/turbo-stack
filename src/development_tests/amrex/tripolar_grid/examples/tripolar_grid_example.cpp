#include <memory>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "tripolar_grid.h"

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
        std::shared_ptr<CartesianGeometry> geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

        // Construct with 2 cells in each direction
        const std::size_t n_cell_x = 4;
        const std::size_t n_cell_y = 8;
        const std::size_t n_cell_z = 16;
        std::shared_ptr<CartesianGrid> grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);

        // Construct tripolar grid based on the Cartesian grid
        TripolarGrid tripolar_grid(grid);

        // Initialize all the scalar MultiFabs to a linear function of x
        tripolar_grid.InitializeScalarMultiFabs([](double x, double y, double z) {
            return x;
        });

        // Initialize all the vector MultiFabs to their x, y, z coordinates
        tripolar_grid.InitializeVectorMultiFabs([](double x, double y, double z) {
            return std::array<double, 3>{x, y, z};
        });

        tripolar_grid.WriteHDF5("tripolar_grid.h5");

    }
    amrex::Finalize();
    return 0;
}