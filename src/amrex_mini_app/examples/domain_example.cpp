#include <cstddef>
#include <memory>
#include <string>
#include <ranges>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "cartesian_domain.h"
#include "cartesian_geometry.h"
#include "cartesian_grid.h"
#include "field.h"

int main(int argc, char* argv[])
{
    amrex::Initialize(argc, argv);
    {
        /////////////////////////////////////////////////////////////////////////////////////////////////
        //  Create a Cartesian Domain
        /////////////////////////////////////////////////////////////////////////////////////////////////

        // I imagine this setup will be done by some high level thing like a simulation class eventually.
        // In its own scope to prevent namespace pollution. 
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

        // Accessors for the domain's geometry, grid, and fields
        const std::shared_ptr<turbo::CartesianGeometry> geometry = domain.GetGeometry();
        const std::shared_ptr<turbo::CartesianGrid> grid = domain.GetGrid();
        auto fields = domain.GetFields(); // fields is a non owning view so it will automatically update when we add fields to the domain

        // Now have access to geometry and grid information if needed... TODO: move this print functionality grid and field into an overload of operator<< later
        amrex::Print() << "Geometry Summary:" << std::endl;
        amrex::Print() << "  X: [" << geometry->XMin() << ", " << geometry->XMax() << "]" << std::endl;
        amrex::Print() << "  Y: [" << geometry->YMin() << ", " << geometry->YMax() << "]" << std::endl;
        amrex::Print() << "  Z: [" << geometry->ZMin() << ", " << geometry->ZMax() << "]" << std::endl;
        amrex::Print() << std::endl;

        amrex::Print() << "Grid Summary:" << std::endl;
        amrex::Print() << "  Number of Cells: (" << grid->NCellI() << ", " << grid->NCellJ() << ", " << grid->NCellK() << ")" << std::endl;
        amrex::Print() << "  Number of Nodes: (" << grid->NNodeI() << ", " << grid->NNodeJ() << ", " << grid->NNodeK() << ")" << std::endl;
        amrex::Print() << std::endl;

        /////////////////////////////////////////////////////////////////////////////////////////////////
        //  Add a bunch of Fields to the Domain
        /////////////////////////////////////////////////////////////////////////////////////////////////
        std::size_t n_component_scalar = 1;
        std::size_t n_component_vector = 3;
        {
            // I imagine this will be done by some high level thing like a simulation class eventually.
            // In its own scope to prevent namespace pollution. 
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

            // You can use the fields directly after creating them. Here we just print out some info about them.
            amrex::Print() << "Use references returned from CreateField():" << std::endl;
            for (const auto& field : {cell_scalar, cell_vector, 
                                      node_scalar, node_vector,
                                      x_face_scalar, x_face_vector,
                                      y_face_scalar, y_face_vector,
                                      z_face_scalar, z_face_vector}) {
                amrex::Print() << *field << std::endl;
            }
        }

        // You can also access the fields via the non-owning view of the fields in the domain that we cretated earlier.
        // We can print the same info about all the fields again here to demonstrate.
        amrex::Print() << "Use references returned from view via GetFields():" << std::endl;
        for (const auto& field : fields) {
            amrex::Print() << *field << std::endl;
        }

        // Create filtered views of the fields with certain properties for easy access later
        using FieldPtr = std::shared_ptr<turbo::Field>;
        auto scalar_fields        = std::views::filter(fields, [n_component_scalar](const FieldPtr& field) { return field->multifab->nComp() == n_component_scalar; });
        auto vector_fields        = std::views::filter(fields, [n_component_vector](const FieldPtr& field) { return field->multifab->nComp() == n_component_vector; });
        auto nodal_fields         = std::views::filter(fields, [](const FieldPtr& field) { return field->IsNodal(); });
        auto cell_centered_fields = std::views::filter(fields, [](const FieldPtr& field) { return field->IsCellCentered(); });
        auto i_face_fields        = std::views::filter(fields, [](const FieldPtr& field) { return field->IsIFaceCentered(); });
        auto j_face_fields        = std::views::filter(fields, [](const FieldPtr& field) { return field->IsJFaceCentered(); });
        auto k_face_fields        = std::views::filter(fields, [](const FieldPtr& field) { return field->IsKFaceCentered(); });

        // Example of using the filtered views to access fields with specific properties. 
        amrex::Print() << "Number of fields: " << fields.size() << std::endl; 
        amrex::Print() << "Number of scalar fields: " << std::ranges::distance(scalar_fields) << std::endl;
        amrex::Print() << "Number of vector fields: " << std::ranges::distance(vector_fields) << std::endl;
        amrex::Print() << "Number of nodal fields: " << std::ranges::distance(nodal_fields) << std::endl;
        amrex::Print() << "Number of cell centered fields: " << std::ranges::distance(cell_centered_fields) << std::endl;
        amrex::Print() << "Number of x-face fields: " << std::ranges::distance(i_face_fields) << std::endl;
        amrex::Print() << "Number of y-face fields: " << std::ranges::distance(j_face_fields) << std::endl;
        amrex::Print() << "Number of z-face fields: " << std::ranges::distance(k_face_fields) << std::endl;

        /////////////////////////////////////////////////////////////////////////////////////////////////
        //  Initialize all the scalar and vector MultiFabs in the Domain - Alternative approach without using Field::Initialize
        /////////////////////////////////////////////////////////////////////////////////////////////////

        for (const auto& field : scalar_fields) {
            amrex::MultiFab& mf = *(field->multifab);
            for (amrex::MFIter mfi(mf); mfi.isValid(); ++mfi) {
                const amrex::Array4<amrex::Real>& array = mf.array(mfi);
                amrex::ParallelFor(mfi.validbox(), [=] AMREX_GPU_DEVICE(int i, int j, int k) {
                    const turbo::Grid::Point grid_point = field->GetGridPoint(i, j, k); 
                    array(i, j, k) = grid_point.x; // Example: initialize scalar field with x-coordinate
                });
            }
        }

        for (const auto& field : vector_fields) {
            amrex::MultiFab& mf = *(field->multifab);
            for (amrex::MFIter mfi(mf); mfi.isValid(); ++mfi) {
                const amrex::Array4<amrex::Real>& array = mf.array(mfi);
                amrex::ParallelFor(mfi.validbox(), [=] AMREX_GPU_DEVICE(int i, int j, int k) {
                    const turbo::Grid::Point grid_point = field->GetGridPoint(i, j, k); 
                    array(i, j, k, 0) = grid_point.x; // Example: initialize vector field component 0 with x-coordinate
                    array(i, j, k, 1) = grid_point.y; // Example: initialize vector field component 1 with y-coordinate
                    array(i, j, k, 2) = grid_point.z; // Example: initialize vector field component 2 with z-coordinate
                });
            }
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////
        //  Write output
        /////////////////////////////////////////////////////////////////////////////////////////////////
        domain.WriteHDF5("domain_example.h5");
    }
    amrex::Finalize();
    return 0;
}
