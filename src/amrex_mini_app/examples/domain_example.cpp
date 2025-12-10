
#include <AMReX.H>
#include <AMReX_MultiFab.H>


#include "geometry.h"
#include "cartesian_grid.h"
#include "field.h"
#include "field_container.h"
#include "domain.h"

int main(int argc, char* argv[])
{
    amrex::Initialize(argc, argv);
    {
        const double x_min = 0.0;
        const double x_max = 1.0;
        const double y_min = 0.0;
        const double y_max = 1.0;
        const double z_min = 0.0;
        const double z_max = 1.0;

        const std::size_t n_cell_x = 4;
        const std::size_t n_cell_y = 8;
        const std::size_t n_cell_z = 16;

        turbo::CartesianDomain domain(x_min, x_max,
                                     y_min, y_max,
                                     z_min, z_max,
                                     n_cell_x,
                                     n_cell_y,
                                     n_cell_z);

        std::shared_ptr<turbo::CartesianGeometry> geometry = domain.GetGeometry();
        std::shared_ptr<turbo::CartesianGrid> grid = domain.GetGrid();
        std::shared_ptr<turbo::FieldContainer> fields = domain.GetFields();

        //domain.InitializeScalarMultiFabs([](double x, double y, double z) { return x; });
        //domain.InitializeVectorMultiFabs([](double x, double y, double z) { return std::array<double, 3>{x, y, z}; });

        domain.WriteHDF5("domain_example.h5");
    }
    amrex::Finalize();
    return 0;
}