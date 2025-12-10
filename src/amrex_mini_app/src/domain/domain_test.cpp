#include <gtest/gtest.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <geometry.h>
#include <cartesian_grid.h>
#include <domain.h>

#include "amrex_test_environment.h"

using namespace turbo;

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());


class CartesianDomainTest : public ::testing::Test {
protected:
    double x_min, x_max, y_min, y_max, z_min, z_max;
    std::size_t n_cell_x, n_cell_y, n_cell_z;

    void SetUp() override {
        x_min = 0.0;
        x_max = 1.0;
        y_min = 0.0;
        y_max = 1.0;
        z_min = 0.0;
        z_max = 1.0;

        // Default grid size for most tests
        n_cell_x = 8;
        n_cell_y = 16;
        n_cell_z = 4;
    }
};

TEST_F(CartesianDomainTest, Constructor) {

    
    CartesianDomain cartesian_domain(x_min, x_max,
                                     y_min, y_max,
                                     z_min, z_max,
                                     n_cell_x,
                                     n_cell_y,
                                     n_cell_z);

}

//TEST_F(CartesianDomainTest, Initialize_Multifabs) {
//
//    Domain domain(grid);
//
//    domain.InitializeScalarMultiFabs([](double x, double y, double z) {
//        return 1.23;
//    });
//
//    for (const std::shared_ptr<amrex::MultiFab>& mf : domain.scalar_multifabs) {
//        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
//            auto arr = mf->array(mfi);
//            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
//                EXPECT_EQ(arr(i, j, k), 1.23);
//            });
//        }
//    }
//
//    domain.InitializeVectorMultiFabs([](double x, double y, double z) {
//        return std::array<double, 3>{1.0, 2.0, 3.0};
//    });
//
//    for (const std::shared_ptr<amrex::MultiFab>& mf : domain.vector_multifabs) {
//        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
//            auto arr = mf->array(mfi);
//            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
//                EXPECT_EQ(arr(i, j, k, 0), 1.0);
//                EXPECT_EQ(arr(i, j, k, 1), 2.0);
//                EXPECT_EQ(arr(i, j, k, 2), 3.0);
//            });
//        }
//    }
//}


TEST_F(CartesianDomainTest, WriteHDF5) {

    CartesianDomain cartesian_domain(x_min, x_max,
                                     y_min, y_max,
                                     z_min, z_max,
                                     n_cell_x,
                                     n_cell_y,
                                     n_cell_z);

    //cartesian_domain.InitializeScalarMultiFabs([](double x, double y, double z) {
    //    return x;
    //});

    //cartesian_domain.InitializeVectorMultiFabs([](double x, double y, double z) {
    //    return std::array<double, 3>{x, y, z};
    //});

    cartesian_domain.WriteHDF5("Test_Output_Domain_WriteHDF5.h5");
}