#include <cstddef>
#include <memory>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "geometry.h"
#include "cartesian_grid.h"
#include "field.h"
#include "field_container.h"

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

        // Create a FieldContainer and add some fields to it
        FieldContainer field_container(grid);
        {
           using FieldPtr = std::shared_ptr<Field>;

           // Example of creating some scalar fields at various staggers with one ghost cell
           FieldPtr temperature_field = field_container.Insert("temperature", FieldGridStagger::CellCentered, 1, 1);
           FieldPtr pressure_field    = field_container.Insert("pressure",    FieldGridStagger::Nodal,        1, 1);

           // Example of storing single component of velocity at the face that velocity is normal to (as is often done for fluxes) and one ghost cell
           FieldPtr x_velocity_field  = field_container.Insert("x_velocity", FieldGridStagger::IFace, 1, 1);
           FieldPtr y_velocity_field  = field_container.Insert("y_velocity", FieldGridStagger::JFace, 1, 1);
           FieldPtr z_velocity_field  = field_container.Insert("z_velocity", FieldGridStagger::KFace, 1, 1);

           // Example of storing a vector field (3 components) at the nodes with no ghost cells
           FieldPtr vorticity_field    = field_container.Insert("vorticity", FieldGridStagger::Nodal, 3, 0);
        }

        // Loop over all the fields in the FieldContainer and print out their names, FieldGridStagger, and MultiFab pointer
        for (const auto& field : field_container) {
            amrex::Print() << "Field name: " << field->name << ", FieldGridStagger: " << FieldGridStaggerToString(field->field_grid_stagger) << ", MultiFab pointer: " << field->multifab.get() << "\n";
        }

        // After we are out of the scope where a field was created and returned by FieldContainer::Insert we can use the FieldContainer::Get function to get that field as long as we know the name.
        std::shared_ptr<Field> temperature_field = field_container.Get("temperature", FieldGridStagger::CellCentered);

        // However if you were somewhere else in the program and you were not sure if a field exists, I recommend using Contains() to check if the field exists before calling Get() to avoid potential exceptions.
        if ( field_container.Contains("temperature", FieldGridStagger::CellCentered) ) {
            std::shared_ptr<Field> also_temperature_field = field_container.Get("temperature", FieldGridStagger::CellCentered);
        } else {
            // In this example we should never get here since we just explicitly added a field named "temperature" above.
            // But in a real user program or application maybe they are using fields that were created somewhere else in the call stack in another scope.
            // I assume people would handle this sort of set up and getting in a way that makes sense for their application. Like maintain a list of valid field names, or use Contains() to check before calling Get() like we do here and creating the needed field if it does not already exist, etc.
            // But in this example I don't handle anything and just throw an exception to bail here.
            throw std::runtime_error("FieldContainer does NOT contain a field named 'temperature'");
        }

    }

    amrex::Finalize();
    return 0;
}