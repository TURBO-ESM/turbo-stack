#include <cstddef> // for std::size_t

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "tripolar_grid.h"

TripolarGrid::TripolarGrid(std::size_t n_cell_x, std::size_t n_cell_y, std::size_t n_cell_z)
    : n_cell_x_(n_cell_x), n_cell_y_(n_cell_y), n_cell_z_(n_cell_z)
{
    // Initialize the MultiFabs

    // number of ghost cells
    const int N_ghost = 1; // Maybe we dont want ghost elements for some of the mutifabs, or only in certain directions, but I just setting it the same for all of them for now.

    // number of components for each array
    const int N_comp_scalar = 1; // Scalar field, e.g., temperature or pressure
    const int N_comp_vector = 3; // Vector field, e.g., velocity (u, v, w)

    // Create MultiFabs for scalar and vector fields on the cell-centered grid
    {
        const amrex::IntVect cell_low_index(0,0,0);
        const amrex::IntVect cell_high_index(n_cell_x - 1, n_cell_y - 1, n_cell_z - 1);
        const amrex::Box cell_centered_box(cell_low_index, cell_high_index);

        amrex::BoxArray cell_box_array(cell_centered_box);
        // Will break up boxarray "cell_box_array" into chunks no larger than "max_chunk_size" along a direction
        const int max_chunk_size = 32; 
        cell_box_array.maxSize(max_chunk_size);

        const amrex::DistributionMapping distribution_mapping(cell_box_array);

        // number of components for each array
        cell_scalar.define(cell_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        cell_vector.define(cell_box_array, distribution_mapping, N_comp_vector, N_ghost);
    }

    // Definging the multfabs on the nodes and faces assume these two are defined on cells. Confirm that.
    AMREX_ASSERT(cell_scalar.is_cell_centered());
    AMREX_ASSERT(cell_vector.is_cell_centered());

    // Create MultiFabs for scalar and vector fields on the x-face-centered grid
    {
        // Convert the cell-centered box array to x-face-centered
        const amrex::BoxArray x_face_box_array = amrex::convert(cell_scalar.boxArray(), amrex::IntVect(1,0,0));

        // Define the MultiFab for x-face-centered scalar field
        x_face_scalar.define(x_face_box_array, cell_scalar.DistributionMap(), N_comp_scalar, N_ghost);
        x_face_vector.define(x_face_box_array, cell_scalar.DistributionMap(), N_comp_vector, N_ghost);
    }

    // Create MultiFabs for scalar and vector fields on the y-face-centered grid
    {
        // Convert the cell-centered box array to y-face-centered
        const amrex::BoxArray y_face_box_array = amrex::convert(cell_scalar.boxArray(), amrex::IntVect(0,1,0));

        // Define the MultiFab for x-face-centered scalar field
        y_face_scalar.define(y_face_box_array, cell_scalar.DistributionMap(), N_comp_scalar, N_ghost);
        y_face_vector.define(y_face_box_array, cell_scalar.DistributionMap(), N_comp_vector, N_ghost);
    }

    // Create MultiFabs for scalar and vector fields on the z-face-centered grid
    {
        // Convert the cell-centered box array to z-face-centered
        const amrex::BoxArray z_face_box_array = amrex::convert(cell_scalar.boxArray(), amrex::IntVect(0,0,1));

        // Define the MultiFab for z-face-centered scalar field
        z_face_scalar.define(z_face_box_array, cell_scalar.DistributionMap(), N_comp_scalar, N_ghost);
        z_face_vector.define(z_face_box_array, cell_scalar.DistributionMap(), N_comp_vector, N_ghost);
    }

    // Create MultiFabs for scalar and vector fields on the nodal grid
    {
        // Convert the cell-centered box array to nodal
        const amrex::BoxArray nodal_box_array = amrex::convert(cell_scalar.boxArray(), amrex::IntVect(1,1,1));

        // Define the MultiFab for nodal scalar field
        node_scalar.define(nodal_box_array, cell_scalar.DistributionMap(), N_comp_scalar, N_ghost);
        node_vector.define(nodal_box_array, cell_scalar.DistributionMap(), N_comp_vector, N_ghost);
    }

}