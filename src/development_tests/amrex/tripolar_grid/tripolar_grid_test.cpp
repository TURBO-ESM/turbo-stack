#include <gtest/gtest.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <tripolar_grid.h>

TEST(TripolarGrid, Constructor) {

    // Fake main arguments argc and argv for AMReX initialization
    int argc = 1;
    char arg0[] = "test";
    char* argv_array[] = { arg0, nullptr };
    char** argv = argv_array; // pointer to the array
    amrex::Initialize(argc,argv);
    {

    std::size_t n_cell_x = 10;
    std::size_t n_cell_y = 20;
    std::size_t n_cell_z = 30;

    TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

    EXPECT_EQ(grid.NCell(),  n_cell_x * n_cell_y * n_cell_z);
    EXPECT_EQ(grid.NCellX(), n_cell_x);
    EXPECT_EQ(grid.NCellY(), n_cell_y);
    EXPECT_EQ(grid.NCellZ(), n_cell_z);

    // Make sure MultiFabs are initialized correctly
    const amrex::MultiFab* const all_multifabs[] = {
        &grid.cell_scalar,   &grid.cell_vector,
        &grid.x_face_scalar, &grid.x_face_vector,
        &grid.y_face_scalar, &grid.y_face_vector,
        &grid.z_face_scalar, &grid.z_face_vector,
        &grid.node_scalar,   &grid.node_vector
    };

    const amrex::MultiFab* const scalar_multifabs[] = {
        &grid.cell_scalar,
        &grid.x_face_scalar,
        &grid.y_face_scalar,
        &grid.z_face_scalar,
        &grid.node_scalar
    };

    const amrex::MultiFab* const vector_multifabs[] = {
        &grid.cell_vector,
        &grid.x_face_vector,
        &grid.y_face_vector,
        &grid.z_face_vector,
        &grid.node_vector
    };

    const amrex::MultiFab* const cell_multifabs[] = {
        &grid.cell_scalar,
        &grid.cell_vector
    };

    const amrex::MultiFab* const x_face_multifabs[] = {
        &grid.x_face_scalar,
        &grid.x_face_vector
    };

    const amrex::MultiFab* const y_face_multifabs[] = {
        &grid.y_face_scalar,
        &grid.y_face_vector
    };

    const amrex::MultiFab* const z_face_multifabs[] = {
        &grid.z_face_scalar,
        &grid.z_face_vector
    };

    const amrex::MultiFab* const node_multifabs[] = {
        &grid.node_scalar,
        &grid.node_vector
    };


    for (const auto* mf : all_multifabs) {
        EXPECT_TRUE(mf->ok());
    }

    for (const auto* mf : scalar_multifabs) {
        EXPECT_EQ(mf->nComp(), 1);
    }

    for (const auto* mf : vector_multifabs) {
        EXPECT_EQ(mf->nComp(), 3);
    }

    for (const auto* mf : cell_multifabs) {
        EXPECT_TRUE(mf->is_cell_centered());
        // TODO: Check that dimensions are correct (nx, ny, nz)

    }

    for (const auto* mf : x_face_multifabs) {
        EXPECT_TRUE(mf->is_nodal(0));
        EXPECT_FALSE(mf->is_nodal(1));
        EXPECT_FALSE(mf->is_nodal(2));
        // TODO: Check that dimensions are correct

    }

    for (const auto* mf : y_face_multifabs) {
        EXPECT_FALSE(mf->is_nodal(0));
        EXPECT_TRUE(mf->is_nodal(1));
        EXPECT_FALSE(mf->is_nodal(2));
        // TODO: Check that dimensions are correct

    }

    for (const auto* mf : z_face_multifabs) {
        EXPECT_FALSE(mf->is_nodal(0));
        EXPECT_FALSE(mf->is_nodal(1));
        EXPECT_TRUE(mf->is_nodal(2));
        // TODO: Check that dimensions are correct
    }

    for (const auto* mf : node_multifabs) {
        EXPECT_TRUE(mf->is_nodal());
        // TODO: Check that dimensions are correct (nx+1, ny+1, nz+1)
    }


    }
    amrex::Finalize();
}