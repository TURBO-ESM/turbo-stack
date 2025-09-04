
#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <tripolar_grid.h>


int main(int argc, char* argv[])
{
    amrex::Initialize(argc, argv);
    {

        const std::size_t n_cell_x = 16;
        const std::size_t n_cell_y = 8;
        const std::size_t n_cell_z = 4;

        TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

        grid.InitializeScalarMultiFabs([](double x, double y, double z) {
            return x;
        });

        grid.InitializeVectorMultiFabs([](double x, double y, double z) {
            return std::array<double, 3>{x, y, z};
        });

        grid.WriteHDF5("tripolar_grid.h5");

    }
    amrex::Finalize();
    return 0;
}