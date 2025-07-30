#include <gtest/gtest.h>

#include <map>

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

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x, n_cell_y, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x-1, n_cell_y-1, n_cell_z-1));

    }

    for (const auto* mf : x_face_multifabs) {
        EXPECT_TRUE(mf->is_nodal(0));
        EXPECT_FALSE(mf->is_nodal(1));
        EXPECT_FALSE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x+1, n_cell_y, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x, n_cell_y-1, n_cell_z-1));

    }

    for (const auto* mf : y_face_multifabs) {
        EXPECT_FALSE(mf->is_nodal(0));
        EXPECT_TRUE(mf->is_nodal(1));
        EXPECT_FALSE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x, n_cell_y+1, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x-1, n_cell_y, n_cell_z-1));

    }

    for (const auto* mf : z_face_multifabs) {
        EXPECT_FALSE(mf->is_nodal(0));
        EXPECT_FALSE(mf->is_nodal(1));
        EXPECT_TRUE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x, n_cell_y, n_cell_z+1));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x-1, n_cell_y-1, n_cell_z));
    }

    for (const auto* mf : node_multifabs) {
        EXPECT_TRUE(mf->is_nodal());

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x+1, n_cell_y+1, n_cell_z+1));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x, n_cell_y, n_cell_z));
    }

    }
    amrex::Finalize();
}

TEST(TripolarGrid, Geometry) {

    // Fake main arguments argc and argv for AMReX initialization
    int argc = 1;
    char arg0[] = "test";
    char* argv_array[] = { arg0, nullptr };
    char** argv = argv_array; // pointer to the array
    amrex::Initialize(argc,argv);
    {

    std::size_t n_cell_x = 2;
    std::size_t n_cell_y = 2;
    std::size_t n_cell_z = 2;

    TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

    std::map<std::size_t, double> index_to_node = {
        {0, 0.0},
        {1, 0.5},
        {2, 1.0}
    };

    for (std::size_t i = 0; i < grid.NNodeX(); ++i) {
        for (std::size_t j = 0; j < grid.NNodeY(); ++j) {
            for (std::size_t k = 0; k < grid.NNodeZ(); ++k) {
                auto node = grid.Node(amrex::IntVect(i, j, k));
                auto expected_node = TripolarGrid::Point({index_to_node[i], index_to_node[j], index_to_node[k]});
                EXPECT_EQ(node.x, expected_node.x);
                EXPECT_EQ(node.y, expected_node.y);
                EXPECT_EQ(node.z, expected_node.z);
            }
        }
    }

    std::map<std::size_t, double> index_to_cell_center = {
        {0, 0.25},
        {1, 0.75},
    };

    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NCellY(); ++j) {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k) {
                auto cell_center = grid.CellCenter(amrex::IntVect(i, j, k));
                auto expected_cell_center = TripolarGrid::Point({index_to_cell_center[i], index_to_cell_center[j], index_to_cell_center[k]});
                EXPECT_EQ(cell_center.x, expected_cell_center.x);
                EXPECT_EQ(cell_center.y, expected_cell_center.y);
                EXPECT_EQ(cell_center.z, expected_cell_center.z);
            }
        }
    }

    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NNodeY(); ++j) {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k) {
                auto point = grid.YFace(amrex::IntVect(i, j, k));
                auto expected_point = TripolarGrid::Point({index_to_cell_center[i], index_to_node[j], index_to_cell_center[k]});
                EXPECT_EQ(point.x, expected_point.x);
                EXPECT_EQ(point.y, expected_point.y);
                EXPECT_EQ(point.z, expected_point.z);
            }
        }
    }

    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NCellY(); ++j) {
            for (std::size_t k = 0; k < grid.NNodeZ(); ++k) {
                auto point = grid.ZFace(amrex::IntVect(i, j, k));
                auto expected_point = TripolarGrid::Point({index_to_cell_center[i], index_to_cell_center[j], index_to_node[k]});
                EXPECT_EQ(point.x, expected_point.x);
                EXPECT_EQ(point.y, expected_point.y);
                EXPECT_EQ(point.z, expected_point.z);
            }
        }
    }


    }
    amrex::Finalize();
}