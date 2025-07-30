#include <cstddef> // for std::size_t

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "tripolar_grid.h"

// Point operator+
TripolarGrid::Point TripolarGrid::Point::operator+(const Point& other) const noexcept {
    return {x + other.x, y + other.y, z + other.z};
}

TripolarGrid::TripolarGrid(std::size_t n_cell_x, std::size_t n_cell_y, std::size_t n_cell_z)
    : n_cell_x_(n_cell_x), n_cell_y_(n_cell_y), n_cell_z_(n_cell_z)
{
    static_assert(
        amrex::SpaceDim == 3,
        "Only supports 3D grids."
    );

    // Initialize the MultiFabs

    // number of ghost cells
    const int N_ghost = 1; // Maybe we dont want ghost elements for some of the mutifabs, or only in certain directions, but I just setting it the same for all of them for now.

    // number of components for each array
    const int N_comp_scalar = 1; // Scalar field, e.g., temperature or pressure
    const int N_comp_vector = 3; // Vector field, e.g., velocity (u, v, w)

    // Create MultiFabs for scalar and vector fields on the cell-centered grid
    {
        // We don't really need the AMREX_D_DECL here since we are enforcing 3D grids only, but it's fine to keep it for now to avoid potential issues if we decide to extend to 2D or 1D later.
        // If or when we do that we will need to wrap all the change the other IntVect definitions accordingly.
        const amrex::IntVect cell_low_index(AMREX_D_DECL(0,0,0));
        const amrex::IntVect cell_high_index(AMREX_D_DECL(n_cell_x - 1, n_cell_y - 1, n_cell_z - 1));
        const amrex::Box cell_centered_box(cell_low_index, cell_high_index);

        amrex::BoxArray cell_box_array(cell_centered_box);
        // Will break up boxarray "cell_box_array" into chunks no larger than "max_chunk_size" along a direction
        const int max_chunk_size = 32; 
        cell_box_array.maxSize(max_chunk_size);

        const amrex::DistributionMapping distribution_mapping(cell_box_array);

        // number of components for each array
        //cell_scalar.define(cell_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        //cell_vector.define(cell_box_array, distribution_mapping, N_comp_vector, N_ghost);

        cell_scalar = std::make_shared<amrex::MultiFab>(cell_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        cell_vector = std::make_shared<amrex::MultiFab>(cell_box_array, distribution_mapping, N_comp_vector, N_ghost);
    }

    // Defining the MultiFab on the nodes and faces assume these two are defined on cells. Confirm that.
    AMREX_ASSERT(cell_scalar.is_cell_centered());
    AMREX_ASSERT(cell_vector.is_cell_centered());

    // All subsequent MultiFabs will be defined based on the cell-centered multifabs distribution mapping. 
    const amrex::DistributionMapping distribution_mapping = cell_scalar->DistributionMap();

    // All subsequent MultiFabs box arrays will be adjusted accordingly using convert and the box array from the cell-centered MultiFabs.
    const amrex::BoxArray& cell_box_array = cell_scalar->boxArray();

    // Create MultiFabs for scalar and vector fields on the x-face-centered grid
    {
        // Convert the cell-centered box array to x-face-centered
        const amrex::BoxArray x_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(1,0,0));

        // Define the MultiFab for x-face-centered scalar field
        //x_face_scalar.define(x_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        //x_face_vector.define(x_face_box_array, distribution_mapping, N_comp_vector, N_ghost);

        x_face_scalar = std::make_shared<amrex::MultiFab>(x_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        x_face_vector = std::make_shared<amrex::MultiFab>(x_face_box_array, distribution_mapping, N_comp_vector, N_ghost);
    }

    // Create MultiFabs for scalar and vector fields on the y-face-centered grid
    {
        // Convert the cell-centered box array to y-face-centered
        const amrex::BoxArray y_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(0,1,0));

        // Define the MultiFab for x-face-centered scalar field
        //y_face_scalar.define(y_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        //y_face_vector.define(y_face_box_array, distribution_mapping, N_comp_vector, N_ghost);

        y_face_scalar = std::make_shared<amrex::MultiFab>(y_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        y_face_vector = std::make_shared<amrex::MultiFab>(y_face_box_array, distribution_mapping, N_comp_vector, N_ghost);

    }

    // Create MultiFabs for scalar and vector fields on the z-face-centered grid
    {
        // Convert the cell-centered box array to z-face-centered
        const amrex::BoxArray z_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(0,0,1));

        // Define the MultiFab for z-face-centered scalar field
        //z_face_scalar.define(z_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        //z_face_vector.define(z_face_box_array, distribution_mapping, N_comp_vector, N_ghost);

        z_face_scalar = std::make_shared<amrex::MultiFab>(z_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        z_face_vector = std::make_shared<amrex::MultiFab>(z_face_box_array, distribution_mapping, N_comp_vector, N_ghost);

    }

    // Create MultiFabs for scalar and vector fields on the nodal grid
    {
        // Convert the cell-centered box array to nodal
        const amrex::BoxArray nodal_box_array = amrex::convert(cell_box_array, amrex::IntVect(1,1,1));

        // Define the MultiFab for nodal scalar field
        //node_scalar.define(nodal_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        //node_vector.define(nodal_box_array, distribution_mapping, N_comp_vector, N_ghost);

        node_scalar = std::make_shared<amrex::MultiFab>(nodal_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        node_vector = std::make_shared<amrex::MultiFab>(nodal_box_array, distribution_mapping, N_comp_vector, N_ghost);
    }

    // Collections of MultiFabs for easier looping and testing
    all_multifabs = {
        cell_scalar,
        cell_vector,
        x_face_scalar,
        x_face_vector,
        y_face_scalar,
        y_face_vector,
        z_face_scalar,
        z_face_vector,
        node_scalar,
        node_vector
    };

    scalar_multifabs = {
        cell_scalar,
        x_face_scalar,
        y_face_scalar,
        z_face_scalar,
        node_scalar,
    };

    vector_multifabs = {
        cell_vector,
        x_face_vector,
        y_face_vector,
        z_face_vector,
        node_vector
    };

    cell_multifabs = {
        cell_scalar,
        cell_vector
    };

    x_face_multifabs = {
        x_face_scalar,
        x_face_vector
    };

    y_face_multifabs = {
        y_face_scalar,
        y_face_vector
    };

    z_face_multifabs = {
        z_face_scalar,
        z_face_vector
    };

    node_multifabs = {
        node_scalar,
        node_vector
    };

}

std::size_t TripolarGrid::NCell() const noexcept  { return n_cell_x_ * n_cell_y_ * n_cell_z_; }
std::size_t TripolarGrid::NCellX() const noexcept { return n_cell_x_; }
std::size_t TripolarGrid::NCellY() const noexcept { return n_cell_y_; }
std::size_t TripolarGrid::NCellZ() const noexcept { return n_cell_z_; }

std::size_t TripolarGrid::NNode() const noexcept  { return NNodeX() * NNodeY() * NNodeZ(); }
std::size_t TripolarGrid::NNodeX() const noexcept { return NCellX() + 1; }
std::size_t TripolarGrid::NNodeY() const noexcept { return NCellY() + 1; }
std::size_t TripolarGrid::NNodeZ() const noexcept { return NCellZ() + 1; }

TripolarGrid::Point TripolarGrid::Node(amrex::IntVect node_index) const noexcept {
    return {x_min_ + node_index[0] * dx_,
            y_min_ + node_index[1] * dy_,
            z_min_ + node_index[2] * dz_};
}

TripolarGrid::Point TripolarGrid::CellCenter(amrex::IntVect cell_index) const noexcept {
    return Node(cell_index) + Point{dx_*0.5, dy_*0.5, dz_*0.5};
}

TripolarGrid::Point TripolarGrid::XFace(amrex::IntVect x_face_index) const noexcept {
    return Node(x_face_index) + Point{0.0, dy_*0.5, dz_*0.5};
}

TripolarGrid::Point TripolarGrid::YFace(amrex::IntVect y_face_index) const noexcept {
    return Node(y_face_index) + Point{dx_*0.5, 0.0, dz_*0.5};
}

TripolarGrid::Point TripolarGrid::ZFace(amrex::IntVect z_face_index) const noexcept {
    return Node(z_face_index) + Point{dx_*0.5, dy_*0.5, 0.0};
}