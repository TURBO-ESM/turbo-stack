#include <AMReX.H>
#include <AMReX_MultiFab.H>
#include <gtest/gtest.h>
#include <tripolar_grid.h>

#include <map>

///////////////////////////////////////////////////////////////////////////////
// Define a global test environment for AMReX
class AmrexEnvironment : public ::testing::Environment
{
   public:
    void SetUp() override
    {
        int argc           = 1;
        char arg0[]        = "test";
        char* argv_array[] = {arg0, nullptr};
        char** argv        = argv_array;
        amrex::Initialize(argc, argv);
    }
    void TearDown() override { amrex::Finalize(); }
};

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());

///////////////////////////////////////////////////////////////////////////////

TEST(TripolarGrid, Constructor)
{
    std::size_t n_cell_x = 10;
    std::size_t n_cell_y = 20;
    std::size_t n_cell_z = 30;

    TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

    EXPECT_EQ(grid.NCell(), n_cell_x * n_cell_y * n_cell_z);
    EXPECT_EQ(grid.NCellX(), n_cell_x);
    EXPECT_EQ(grid.NCellY(), n_cell_y);
    EXPECT_EQ(grid.NCellZ(), n_cell_z);

    for (const auto& mf : grid.all_multifabs)
    {
        EXPECT_TRUE(mf->ok());
    }

    for (const auto& mf : grid.scalar_multifabs)
    {
        EXPECT_EQ(mf->nComp(), 1);
    }

    for (const auto& mf : grid.vector_multifabs)
    {
        EXPECT_EQ(mf->nComp(), 3);
    }

    for (const auto& mf : grid.cell_multifabs)
    {
        EXPECT_TRUE(mf->is_cell_centered());

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(), amrex::IntVect(n_cell_x, n_cell_y, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(), amrex::IntVect(n_cell_x - 1, n_cell_y - 1, n_cell_z - 1));
    }

    for (const auto& mf : grid.x_face_multifabs)
    {
        EXPECT_TRUE(mf->is_nodal(0));
        EXPECT_FALSE(mf->is_nodal(1));
        EXPECT_FALSE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(), amrex::IntVect(n_cell_x + 1, n_cell_y, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(), amrex::IntVect(n_cell_x, n_cell_y - 1, n_cell_z - 1));
    }

    for (const auto& mf : grid.y_face_multifabs)
    {
        EXPECT_FALSE(mf->is_nodal(0));
        EXPECT_TRUE(mf->is_nodal(1));
        EXPECT_FALSE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(), amrex::IntVect(n_cell_x, n_cell_y + 1, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(), amrex::IntVect(n_cell_x - 1, n_cell_y, n_cell_z - 1));
    }

    for (const auto& mf : grid.z_face_multifabs)
    {
        EXPECT_FALSE(mf->is_nodal(0));
        EXPECT_FALSE(mf->is_nodal(1));
        EXPECT_TRUE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(), amrex::IntVect(n_cell_x, n_cell_y, n_cell_z + 1));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(), amrex::IntVect(n_cell_x - 1, n_cell_y - 1, n_cell_z));
    }

    for (const auto& mf : grid.node_multifabs)
    {
        EXPECT_TRUE(mf->is_nodal());

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(), amrex::IntVect(n_cell_x + 1, n_cell_y + 1, n_cell_z + 1));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(), amrex::IntVect(n_cell_x, n_cell_y, n_cell_z));
    }
}

TEST(TripolarGrid, Geometry)
{
    std::size_t n_cell_x = 2;
    std::size_t n_cell_y = 2;
    std::size_t n_cell_z = 2;

    TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

    std::map<std::size_t, double> index_to_node = {{0, 0.0}, {1, 0.5}, {2, 1.0}};

    for (std::size_t i = 0; i < grid.NNodeX(); ++i)
    {
        for (std::size_t j = 0; j < grid.NNodeY(); ++j)
        {
            for (std::size_t k = 0; k < grid.NNodeZ(); ++k)
            {
                auto node          = grid.Node(amrex::IntVect(i, j, k));
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

    for (std::size_t i = 0; i < grid.NCellX(); ++i)
    {
        for (std::size_t j = 0; j < grid.NCellY(); ++j)
        {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k)
            {
                auto cell_center = grid.CellCenter(amrex::IntVect(i, j, k));
                auto expected_cell_center =
                    TripolarGrid::Point({index_to_cell_center[i], index_to_cell_center[j], index_to_cell_center[k]});
                EXPECT_EQ(cell_center.x, expected_cell_center.x);
                EXPECT_EQ(cell_center.y, expected_cell_center.y);
                EXPECT_EQ(cell_center.z, expected_cell_center.z);
            }
        }
    }

    for (std::size_t i = 0; i < grid.NCellX(); ++i)
    {
        for (std::size_t j = 0; j < grid.NNodeY(); ++j)
        {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k)
            {
                auto point = grid.YFace(amrex::IntVect(i, j, k));
                auto expected_point =
                    TripolarGrid::Point({index_to_cell_center[i], index_to_node[j], index_to_cell_center[k]});
                EXPECT_EQ(point.x, expected_point.x);
                EXPECT_EQ(point.y, expected_point.y);
                EXPECT_EQ(point.z, expected_point.z);
            }
        }
    }

    for (std::size_t i = 0; i < grid.NCellX(); ++i)
    {
        for (std::size_t j = 0; j < grid.NCellY(); ++j)
        {
            for (std::size_t k = 0; k < grid.NNodeZ(); ++k)
            {
                auto point = grid.ZFace(amrex::IntVect(i, j, k));
                auto expected_point =
                    TripolarGrid::Point({index_to_cell_center[i], index_to_cell_center[j], index_to_node[k]});
                EXPECT_EQ(point.x, expected_point.x);
                EXPECT_EQ(point.y, expected_point.y);
                EXPECT_EQ(point.z, expected_point.z);
            }
        }
    }
}

TEST(TripolarGrid, Initialize_Multifabs)
{
    std::size_t n_cell_x = 2;
    std::size_t n_cell_y = 2;
    std::size_t n_cell_z = 2;

    TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

    grid.InitializeScalarMultiFabs([](double x, double y, double z) { return 1.23; });

    for (const std::shared_ptr<amrex::MultiFab>& mf : grid.scalar_multifabs)
    {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi)
        {
            auto arr = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(),
                               [=, this] AMREX_GPU_DEVICE(int i, int j, int k) { EXPECT_EQ(arr(i, j, k), 1.23); });
        }
    }

    grid.InitializeVectorMultiFabs([](double x, double y, double z) { return std::array<double, 3>{1.0, 2.0, 3.0}; });

    for (const std::shared_ptr<amrex::MultiFab>& mf : grid.vector_multifabs)
    {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi)
        {
            auto arr = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(),
                               [=, this] AMREX_GPU_DEVICE(int i, int j, int k)
                               {
                                   EXPECT_EQ(arr(i, j, k, 0), 1.0);
                                   EXPECT_EQ(arr(i, j, k, 1), 2.0);
                                   EXPECT_EQ(arr(i, j, k, 2), 3.0);
                               });
        }
    }
}

TEST(TripolarGrid, WriteHDF5)
{
    const std::size_t n_cell_x = 2;
    const std::size_t n_cell_y = 2;
    const std::size_t n_cell_z = 2;

    TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

    grid.InitializeScalarMultiFabs([](double x, double y, double z) { return 2.0; });

    grid.InitializeVectorMultiFabs([](double x, double y, double z) { return std::array<double, 3>{1.0, 2.0, 3.0}; });

    amrex::Print() << "Initialized scalar and vector MultiFabs." << std::endl;
    grid.WriteHDF5("test.h5");
}