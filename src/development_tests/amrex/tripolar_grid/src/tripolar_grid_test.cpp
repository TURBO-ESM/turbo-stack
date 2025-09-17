#include <gtest/gtest.h>

#include <map>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <geometry.h>
#include <grid.h>
#include <tripolar_grid.h>

using namespace turbo;

///////////////////////////////////////////////////////////////////////////////
// Define a global test environment for AMReX
class AmrexEnvironment : public ::testing::Environment {
public:
    void SetUp() override {
        int argc = 1;
        char arg0[] = "test";
        char* argv_array[] = { arg0, nullptr };
        char** argv = argv_array;
        amrex::Initialize(argc, argv);
    }
    void TearDown() override {
        amrex::Finalize();
    }
};

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());

///////////////////////////////////////////////////////////////////////////////

TEST(TripolarGrid, Constructor) {

    // Simple unit cube geometry
    const double x_min = 0.0;
    const double x_max = 1.0;
    const double y_min = 0.0;
    const double y_max = 1.0;
    const double z_min = 0.0;
    const double z_max = 1.0;
    CartesianGeometry geom(x_min, x_max, y_min, y_max, z_min, z_max);
    // Construct with 2 cells in each direction
    const std::size_t n_cell_x = 10;
    const std::size_t n_cell_y = 20;
    const std::size_t n_cell_z = 30;
    auto grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);
    // Construct tripolar grid based on the Cartesian grid
    TripolarGrid fields(grid);

    //const std::size_t n_cell_x = 10;
    //const std::size_t n_cell_y = 20;
    //const std::size_t n_cell_z = 30;
    //TripolarGrid fields(n_cell_x, n_cell_y, n_cell_z);

    for (const auto& mf : fields.all_multifabs) {
        EXPECT_TRUE(mf->ok());
    }

    for (const auto& mf : fields.scalar_multifabs) {
        EXPECT_EQ(mf->nComp(), 1);
    }

    for (const auto& mf : fields.vector_multifabs) {
        EXPECT_EQ(mf->nComp(), 3);
    }

    for (const auto& mf : fields.cell_multifabs) {
        EXPECT_TRUE(mf->is_cell_centered());

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x, n_cell_y, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x-1, n_cell_y-1, n_cell_z-1));
    }

    for (const auto& mf : fields.x_face_multifabs) {
        EXPECT_TRUE(mf->is_nodal(0));
        EXPECT_FALSE(mf->is_nodal(1));
        EXPECT_FALSE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x+1, n_cell_y, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x, n_cell_y-1, n_cell_z-1));
    }

    for (const auto& mf : fields.y_face_multifabs) {
        EXPECT_FALSE(mf->is_nodal(0));
        EXPECT_TRUE(mf->is_nodal(1));
        EXPECT_FALSE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x, n_cell_y+1, n_cell_z));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x-1, n_cell_y, n_cell_z-1));
    }

    for (const auto& mf : fields.z_face_multifabs) {
        EXPECT_FALSE(mf->is_nodal(0));
        EXPECT_FALSE(mf->is_nodal(1));
        EXPECT_TRUE(mf->is_nodal(2));

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x, n_cell_y, n_cell_z+1));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x-1, n_cell_y-1, n_cell_z));
    }

    for (const auto& mf : fields.node_multifabs) {
        EXPECT_TRUE(mf->is_nodal());

        const amrex::Box& box = mf->boxArray().minimalBox();
        EXPECT_EQ(box.length(),   amrex::IntVect(n_cell_x+1, n_cell_y+1, n_cell_z+1));
        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
        EXPECT_EQ(box.bigEnd(),   amrex::IntVect(n_cell_x, n_cell_y, n_cell_z));
    }

}


TEST(TripolarGrid, Initialize_Multifabs) {

    //std::size_t n_cell_x = 2;
    //std::size_t n_cell_y = 2;
    //std::size_t n_cell_z = 2;
    //TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);

    // Simple unit cube geometry
    const double x_min = 0.0;
    const double x_max = 1.0;
    const double y_min = 0.0;
    const double y_max = 1.0;
    const double z_min = 0.0;
    const double z_max = 1.0;
    CartesianGeometry geom(x_min, x_max, y_min, y_max, z_min, z_max);
    // Construct with 2 cells in each direction
    const std::size_t n_cell_x = 10;
    const std::size_t n_cell_y = 20;
    const std::size_t n_cell_z = 30;
    auto grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);
    // Construct tripolar grid based on the Cartesian grid
    TripolarGrid fields(grid);

    fields.InitializeScalarMultiFabs([](double x, double y, double z) {
        return 1.23;
    });

    for (const std::shared_ptr<amrex::MultiFab>& mf : fields.scalar_multifabs) {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
            auto arr = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
                EXPECT_EQ(arr(i, j, k), 1.23);
            });
        }
    }

    fields.InitializeVectorMultiFabs([](double x, double y, double z) {
        return std::array<double, 3>{1.0, 2.0, 3.0};
    });

    for (const std::shared_ptr<amrex::MultiFab>& mf : fields.vector_multifabs) {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
            auto arr = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
                EXPECT_EQ(arr(i, j, k, 0), 1.0);
                EXPECT_EQ(arr(i, j, k, 1), 2.0);
                EXPECT_EQ(arr(i, j, k, 2), 3.0);
            });
        }
    }

}


//TEST(TripolarGrid, WriteHDF5) {
//
//    const std::size_t n_cell_x = 2;
//    const std::size_t n_cell_y = 2;
//    const std::size_t n_cell_z = 2;
//
//    TripolarGrid grid(n_cell_x, n_cell_y, n_cell_z);
//
//    grid.InitializeScalarMultiFabs([](double x, double y, double z) {
//        return 2.0;
//    });
//
//    grid.InitializeVectorMultiFabs([](double x, double y, double z) {
//        return std::array<double, 3>{1.0, 2.0, 3.0};
//    });
//
//    amrex::Print() << "Initialized scalar and vector MultiFabs." << std::endl;
//    grid.WriteHDF5("test.h5");
//
//}