#include <cstddef>
#include <memory>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "geometry.h"
#include "grid.h"
#include "field.h"

using namespace turbo;

int main(int argc, char* argv[])
{
    amrex::Initialize(argc, argv);
    {
        std::shared_ptr<CartesianGeometry> geometry;
        {
            const double x_min = 0.0;
            const double x_max = 1.0;
            const double y_min = 0.0;
            const double y_max = 1.0;
            const double z_min = 0.0;
            const double z_max = 1.0;
            geometry = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);
        }


        std::shared_ptr<CartesianGrid> grid;
        {
            const std::size_t n_cell_x = 4;
            const std::size_t n_cell_y = 8;
            const std::size_t n_cell_z = 16;
            grid = std::make_shared<CartesianGrid>(geometry, n_cell_x, n_cell_y, n_cell_z);
        }

        // Construct tripolar grid based on the Cartesian grid
        FieldContainer field_container(grid);
    field_container.Insert("c", FieldGridStagger::CellCentered, 1, 1);

        for (const auto& field : field_container) {
            amrex::Print() << "Field name: " << field->name << ", MultiFab pointer: " << field->multifab.get() << "\n";
        }


    }
    amrex::Finalize();
    return 0;
}