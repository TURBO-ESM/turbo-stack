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

    }
    amrex::Finalize();
}