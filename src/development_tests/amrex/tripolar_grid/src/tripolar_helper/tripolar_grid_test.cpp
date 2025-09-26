#include <gtest/gtest.h>

#include <map>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <geometry.h>
#include <grid.h>
#include <tripolar_grid.h>

using namespace turbo;

//---------------------------------------------------------------------------//
// Define a global test environment for AMReX
//---------------------------------------------------------------------------//
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

//---------------------------------------------------------------------------//
// Define a global test environment for AMReX
//---------------------------------------------------------------------------//
TEST(TripolarGrid, Constructor) {
    // Simple unit cube geometry
    const double x_min = 0.0;
    const double x_max = 1.0;
    const double y_min = 0.0;
    const double y_max = 1.0;
    const double z_min = 0.0;
    const double z_max = 1.0;
    std::shared_ptr<CartesianGeometry> geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    // Construct with grid with user specified number of cells in each direction
    const std::size_t n_cell_x = 10;
    const std::size_t n_cell_y = 20;
    const std::size_t n_cell_z = 30;
    std::shared_ptr<CartesianGrid> grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);

    // Construct tripolar grid based on the Cartesian grid
    TripolarGrid tripolar_grid(grid);

    // Check exceptions for invalid constructor arguments
    EXPECT_THROW(TripolarGrid tripolar_grid(nullptr), std::invalid_argument);

}

TEST(TripolarGrid, Initialize_Multifabs) {
    // Simple unit cube geometry
    const double x_min = 0.0;
    const double x_max = 1.0;
    const double y_min = 0.0;
    const double y_max = 1.0;
    const double z_min = 0.0;
    const double z_max = 1.0;
    std::shared_ptr<CartesianGeometry> geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    // Construct with grid with user specified number of cells in each direction
    const std::size_t n_cell_x = 10;
    const std::size_t n_cell_y = 20;
    const std::size_t n_cell_z = 30;
    std::shared_ptr<CartesianGrid> grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);

    // Construct tripolar grid based on the Cartesian grid
    TripolarGrid tripolar_grid(grid);

    tripolar_grid.InitializeScalarMultiFabs([](double x, double y, double z) {
        return 1.23;
    });

    for (const std::shared_ptr<amrex::MultiFab>& mf : tripolar_grid.scalar_multifabs) {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
            auto arr = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
                EXPECT_EQ(arr(i, j, k), 1.23);
            });
        }
    }

    tripolar_grid.InitializeVectorMultiFabs([](double x, double y, double z) {
        return std::array<double, 3>{1.0, 2.0, 3.0};
    });

    for (const std::shared_ptr<amrex::MultiFab>& mf : tripolar_grid.vector_multifabs) {
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


TEST(TripolarGrid, WriteHDF5) {

    // Simple unit cube geometry
    const double x_min = 0.0;
    const double x_max = 1.0;
    const double y_min = 0.0;
    const double y_max = 1.0;
    const double z_min = 0.0;
    const double z_max = 1.0;
    std::shared_ptr<CartesianGeometry> geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    // Construct with grid with user specified number of cells in each direction
    const std::size_t n_cell_x = 2;
    const std::size_t n_cell_y = 2;
    const std::size_t n_cell_z = 2;
    std::shared_ptr<CartesianGrid> grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);

    // Construct tripolar grid based on the Cartesian grid
    TripolarGrid tripolar_grid(grid);

    tripolar_grid.InitializeScalarMultiFabs([](double x, double y, double z) {
        return x;
    });

    tripolar_grid.InitializeVectorMultiFabs([](double x, double y, double z) {
        return std::array<double, 3>{x, y, z};
    });

    tripolar_grid.WriteHDF5("Test_Output_TripolarGrid_WriteHDF5.h5");

}