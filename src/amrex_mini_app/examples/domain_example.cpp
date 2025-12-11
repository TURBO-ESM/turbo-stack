#include <cstddef>
#include <iostream>
#include <memory>
#include <string>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "geometry.h"
#include "cartesian_grid.h"
#include "field.h"
#include "field_container.h"

#include "cartesian_domain.h"

int main(int argc, char* argv[])
{
    amrex::Initialize(argc, argv);
    {
        // I imagine this setup will be done by some high level thing like a simulation class eventually.
        // In it's own scope to prevent namespace pollution. 
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

        // Access the geometry, grid, and fields from the domain
        std::shared_ptr<turbo::CartesianGeometry> geometry = domain.GetGeometry();
        std::shared_ptr<turbo::CartesianGrid> grid = domain.GetGrid();
        // Fields is a non owning view so it will automatically update when we add fields to the domain
        auto fields = domain.GetFields();

        {
            // I imagine this will be done by some high level thing like a simulation class eventually.
            // In it's own scope to prevent namespace pollution. 
            std::size_t n_component_scalar = 1;
            std::size_t n_component_vector = 3;
            std::size_t n_ghost = 1;

            std::shared_ptr<turbo::Field> cell_scalar = domain.CreateField("cell_scalar", turbo::FieldGridStagger::CellCentered, n_component_scalar, n_ghost);
            std::shared_ptr<turbo::Field> cell_vector = domain.CreateField("cell_vector", turbo::FieldGridStagger::CellCentered, n_component_vector, n_ghost);

            std::shared_ptr<turbo::Field> node_scalar = domain.CreateField("node_scalar", turbo::FieldGridStagger::Nodal, n_component_scalar, n_ghost);
            std::shared_ptr<turbo::Field> node_vector = domain.CreateField("node_vector", turbo::FieldGridStagger::Nodal, n_component_vector, n_ghost);

            std::shared_ptr<turbo::Field> x_face_scalar = domain.CreateField("x_face_scalar", turbo::FieldGridStagger::IFace, n_component_scalar, n_ghost);
            std::shared_ptr<turbo::Field> x_face_vector = domain.CreateField("x_face_vector", turbo::FieldGridStagger::IFace, n_component_vector, n_ghost);

            std::shared_ptr<turbo::Field> y_face_scalar = domain.CreateField("y_face_scalar", turbo::FieldGridStagger::JFace, n_component_scalar, n_ghost);
            std::shared_ptr<turbo::Field> y_face_vector = domain.CreateField("y_face_vector", turbo::FieldGridStagger::JFace, n_component_vector, n_ghost);

            std::shared_ptr<turbo::Field> z_face_scalar = domain.CreateField("z_face_scalar", turbo::FieldGridStagger::KFace, n_component_scalar, n_ghost);
            std::shared_ptr<turbo::Field> z_face_vector = domain.CreateField("z_face_vector", turbo::FieldGridStagger::KFace, n_component_vector, n_ghost);
        }


        // Print some stats about the domain and its fields
        amrex::Print() << "Number of fields: " << fields.size() << std::endl; 
        for (const auto& field : fields) {
            amrex::Print() << *field << std::endl;
        }

        //domain.InitializeScalarMultiFabs([](double x, double y, double z) { return x; });
        //domain.InitializeVectorMultiFabs([](double x, double y, double z) { return std::array<double, 3>{x, y, z}; });

        domain.WriteHDF5("domain_example.h5");
    }
    amrex::Finalize();
    return 0;
}